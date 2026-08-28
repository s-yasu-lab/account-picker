#!/bin/bash
#
# ============================================================
#  AccountPicker かんたんインストーラ（これ1ファイルで完結）
# ============================================================
#
#  License: MIT（無保証・自己責任でご利用ください）
#  Privacy: このスクリプトとアプリはネットワーク通信を一切行いません。
#           すべての処理はあなたのMacの中だけで完結し、閲覧履歴や
#           アカウント情報をどこにも送信・保存しません。
#           読み取るのは Chrome のプロファイル一覧（名前とメール
#           アドレス）のみで、選択肢の表示だけに使います。
#
#  使い方（ターミナルに1行貼り付けるだけ）:
#
#    インストール      bash ~/Downloads/install.sh
#    動作診断          bash ~/Downloads/install.sh --doctor
#    アンインストール  bash ~/Downloads/install.sh --uninstall
#
#  このスクリプトがやること:
#    1. アプリ本体(AppleScript)を自動コンパイル → ~/Applications/AccountPicker.app
#    2. http/https を受け取れるよう Info.plist を自動設定
#    3. 署名・LaunchServices 登録を自動実行
#    4. 設定ファイル ~/.config/accountpicker/accounts.txt を作成（既存なら保持）
#    5. インストール結果を自動検証
#    6. 希望すれば、その場でデフォルトブラウザに設定
#       （macOS の確認ダイアログで「使用」を押すだけ）
#
set -u

APP_NAME="AccountPicker"
BUNDLE_ID="com.local.accountpicker"   # 変更する場合は下の JXA 内の同じ文字列も変更
APP_DIR="$HOME/Applications"
APP="$APP_DIR/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"
CONFIG_DIR="$HOME/.config/accountpicker"
CONFIG="$CONFIG_DIR/accounts.txt"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m')
YELLOW=$(printf '\033[33m'); BOLD=$(printf '\033[1m'); RESET=$(printf '\033[0m')
ok()   { echo "  ${GREEN}✔${RESET} $1"; }
ng()   { echo "  ${RED}✘${RESET} $1"; }
info() { echo "  ${YELLOW}→${RESET} $1"; }
die()  { echo; ng "$1"; echo; echo "  原因調査: bash \"$0\" --doctor の結果を確認してください。"; exit 1; }

# ------------------------------------------------------------
# アプリ本体（AppleScript ソース）
# ------------------------------------------------------------
applescript_source() {
cat <<'APPLESCRIPT'
(* AccountPicker - アカウント選択ランチャー（インストーラ内蔵版） *)

property defaultBrowser : "Google Chrome"
property promptTitle : "どのアカウントで開きますか？"
property configRelPath : ".config/accountpicker/accounts.txt"

-- 外部アプリでリンクをクリックしたときの入り口
on open location theURL
	try
		main(theURL)
	on error errMsg number errNum
		reportError(errMsg, errNum, theURL)
	end try
end open location

-- ローカルの .html などを開いたとき
on open theItems
	repeat with anItem in theItems
		try
			main("file://" & (POSIX path of (anItem as alias)))
		on error errMsg number errNum
			reportError(errMsg, errNum, "(file)")
		end try
	end repeat
end open

-- アイコンをダブルクリックしたとき（メンテナンスメニュー）
on run
	activate
	try
		set theChoice to button returned of (display dialog ¬
			"AccountPicker メンテナンスメニュー" buttons ¬
			{"プロファイル一覧", "設定を編集", "動作テスト"} ¬
			default button 3 with title "AccountPicker")
	on error number -128
		return
	end try
	try
		if theChoice is "動作テスト" then
			main("https://docs.google.com/")
		else if theChoice is "設定を編集" then
			ensureConfig()
			do shell script "open -e " & quoted form of configPath()
		else
			showProfiles()
		end if
	on error errMsg number errNum
		reportError(errMsg, errNum, theChoice)
	end try
end run

-- ========================= メイン処理 =========================

on main(theURL)
	-- Chrome から現在のプロファイル一覧を自動取得（追加・削除・改名を自動反映）
	set entries to loadAutoEntries()

	-- Chrome の情報が読めないときだけ、設定ファイル(accounts.txt)を代わりに使う
	if (count of entries) is 0 then
		ensureConfig()
		set entries to loadEntries()
	end if

	if (count of entries) is 0 then
		activate
		display dialog "Chrome のプロファイル情報を取得できず、" & return & ¬
			"設定ファイルにも有効なアカウントがありません。" & return & ¬
			configPath() buttons {"設定を編集"} default button 1 with icon caution
		do shell script "open -e " & quoted form of configPath()
		return
	end if

	set displayList to {}
	repeat with e in entries
		set end of displayList to item 1 of e
	end repeat

	set shownURL to theURL
	if (length of shownURL) > 90 then set shownURL to (text 1 thru 90 of shownURL) & "…"

	activate
	set picked to choose from list displayList ¬
		with title "AccountPicker" ¬
		with prompt promptTitle & return & return & shownURL ¬
		default items {item 1 of displayList} ¬
		OK button name "開く" cancel button name "キャンセル"

	if picked is false then return

	set pickedName to item 1 of picked
	repeat with i from 1 to count of entries
		if item 1 of (item i of entries) is pickedName then
			openWith(item 2 of (item i of entries), theURL)
			return
		end if
	end repeat
end main

-- spec: "Profile 1" 等 / "incognito" / "app:Safari"
on openWith(theSpec, theURL)
	set qURL to ""
	if theURL is not "" then set qURL to " " & quoted form of theURL

	if theSpec is "incognito" then
		do shell script "open -na " & quoted form of defaultBrowser & ¬
			" --args --incognito" & qURL
	else if theSpec starts with "app:" then
		set appName to trim(text 5 thru -1 of theSpec)
		do shell script "open -a " & quoted form of appName & qURL
	else
		do shell script "open -na " & quoted form of defaultBrowser & ¬
			" --args --profile-directory=" & quoted form of theSpec & qURL
	end if
end openWith

-- ======================== 設定ファイル ========================

on configPath()
	return (POSIX path of (path to home folder)) & configRelPath
end configPath

on ensureConfig()
	set p to configPath()
	do shell script "mkdir -p " & quoted form of ¬
		((POSIX path of (path to home folder)) & ".config/accountpicker")
	try
		do shell script "test -f " & quoted form of p
	on error
		set defaultText to "# AccountPicker 設定ファイル
# 書式（1行1アカウント）: 表示名 | プロファイル指定 | メモ（省略可）
# プロファイル指定に書けるもの:
#   Default / Profile 1 / Profile 2 ...  Chrome のプロファイルフォルダ名
#   incognito                            シークレットウィンドウ
#   app:Safari                           別アプリでそのまま開く
# フォルダ名の調べ方: アプリをダブルクリック →「プロファイル一覧」

A社用 | Profile 1 | taro@example.co.jp
B社用 | Profile 2 | hanako@example.ne.jp
プライベート | Default | taro@example.com
シークレットウィンドウ | incognito | 足跡を残さない
Safari で開く | app:Safari
"
		writeUTF8(p, defaultText)
	end try
end ensureConfig

on loadEntries()
	set entries to {}
	try
		set raw to readUTF8(configPath())
	on error
		return entries
	end try
	repeat with aLine in (paragraphs of raw)
		set l to trim(aLine as text)
		if l is not "" and l does not start with "#" then
			set parts to splitText(l, "|")
			if (count of parts) ≥ 2 then
				set lbl to trim(item 1 of parts)
				set spec to trim(item 2 of parts)
				if (count of parts) ≥ 3 then
					set memo to trim(item 3 of parts)
					if memo is not "" then set lbl to lbl & "　― " & memo
				end if
				if lbl is not "" and spec is not "" then ¬
					set end of entries to {lbl, spec}
			end if
		end if
	end repeat
	return entries
end loadEntries

-- ========= Chrome からプロファイルを自動取得（増減・改名を自動反映） =========

on loadAutoEntries()
	set jxa to "const p = $.NSHomeDirectory().js + '/Library/Application Support/Google/Chrome/Local State';
const s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null).js;
const info = JSON.parse(s).profile.info_cache;
Object.keys(info).sort().map(k => [k, (info[k].name || ''), (info[k].user_name || '')].join('\\t')).join('\\n');"
	set entries to {}
	try
		set rawText to do shell script "osascript -l JavaScript -e " & quoted form of jxa
	on error
		return entries
	end try
	repeat with aLine in (paragraphs of rawText)
		set parts to splitText(aLine as text, tab)
		if (count of parts) ≥ 1 then
			set dirName to trim(item 1 of parts)
			set dispName to ""
			set mailAddr to ""
			if (count of parts) ≥ 2 then set dispName to trim(item 2 of parts)
			if (count of parts) ≥ 3 then set mailAddr to trim(item 3 of parts)
			if dirName is not "" then
				set lbl to dispName
				if lbl is "" then set lbl to dirName
				if mailAddr is not "" then set lbl to lbl & "　― " & mailAddr
				set end of entries to {lbl, dirName}
			end if
		end if
	end repeat
	if (count of entries) > 0 then ¬
		set end of entries to {"シークレットウィンドウ　― 足跡を残さない", "incognito"}
	return entries
end loadAutoEntries

-- ================ Chrome プロファイル一覧の表示 ================

on showProfiles()
	set jxa to "const p = $.NSHomeDirectory().js + '/Library/Application Support/Google/Chrome/Local State';
const s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null).js;
const info = JSON.parse(s).profile.info_cache;
Object.keys(info).sort().map(k => k + '  →  ' + (info[k].name || '') + '  ' + (info[k].user_name || '')).join('\\n');"
	try
		set profileText to do shell script "osascript -l JavaScript -e " & quoted form of jxa
	on error
		set profileText to "Chrome の情報を読み取れませんでした。" & return & ¬
			"Chrome で chrome://version を開き、「プロフィール パス」の" & return & ¬
			"末尾のフォルダ名を確認してください。"
	end try
	activate
	display dialog "設定ファイルの2列目には、矢印の左側の値を書いてください。" & ¬
		return & return & profileText buttons {"設定を編集", "OK"} ¬
		default button 2 with title "Chrome プロファイル一覧"
	if button returned of result is "設定を編集" then
		ensureConfig()
		do shell script "open -e " & quoted form of configPath()
	end if
end showProfiles

-- ======================== エラー表示 ========================

on reportError(errMsg, errNum, contextText)
	activate
	try
		display dialog "AccountPicker でエラーが発生しました。" & return & return & ¬
			"エラー " & errNum & ": " & errMsg & return & return & contextText ¬
			buttons {"詳細をコピー", "OK"} default button 2 with icon caution
		if button returned of result is "詳細をコピー" then
			set the clipboard to ("AccountPicker error " & errNum & ": " & ¬
				errMsg & " / " & contextText)
		end if
	end try
end reportError

-- ======================== 汎用ヘルパー ========================

on readUTF8(p)
	return (read (POSIX file p) as «class utf8»)
end readUTF8

on writeUTF8(p, t)
	set f to open for access (POSIX file p) with write permission
	try
		set eof of f to 0
		write t to f as «class utf8»
	end try
	close access f
end writeUTF8

on trim(t)
	set t to t as text
	repeat while t is not "" and (character 1 of t is in {" ", tab})
		if (length of t) is 1 then return ""
		set t to text 2 thru -1 of t
	end repeat
	repeat while t is not "" and (character -1 of t is in {" ", tab})
		if (length of t) is 1 then return ""
		set t to text 1 thru -2 of t
	end repeat
	return t
end trim

on splitText(t, delim)
	set {oldTID, AppleScript's text item delimiters} to ¬
		{AppleScript's text item delimiters, delim}
	set parts to text items of t
	set AppleScript's text item delimiters to oldTID
	return parts
end splitText
APPLESCRIPT
}

# ------------------------------------------------------------
# 補助関数
# ------------------------------------------------------------

require_macos() {
	[ "$(uname)" = "Darwin" ] || die "このスクリプトは macOS 専用です。"
}

current_https_handler() {
	osascript -l JavaScript -e '
ObjC.import("AppKit");
const u = $.NSURL.URLWithString("https://example.com");
const a = $.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL(u);
a.isNil() ? "(不明)" : (function () {
	const b = $.NSBundle.bundleWithURL(a);
	return (b.isNil() || b.bundleIdentifier.isNil()) ? a.path.js : b.bundleIdentifier.js;
})();
' 2>/dev/null
}

write_default_config() {
	if [ -f "$CONFIG" ]; then
		ok "設定ファイルは既に存在（内容を保持）: $CONFIG"
		return
	fi
	mkdir -p "$CONFIG_DIR"
	cat > "$CONFIG" <<'CONF'
# AccountPicker 設定ファイル
# 書式（1行1アカウント）: 表示名 | プロファイル指定 | メモ（省略可）
# プロファイル指定に書けるもの:
#   Default / Profile 1 / Profile 2 ...  Chrome のプロファイルフォルダ名
#   incognito                            シークレットウィンドウ
#   app:Safari                           別アプリでそのまま開く
# フォルダ名の調べ方: アプリをダブルクリック →「プロファイル一覧」

A社用 | Profile 1 | taro@example.co.jp
B社用 | Profile 2 | hanako@example.ne.jp
プライベート | Default | taro@example.com
シークレットウィンドウ | incognito | 足跡を残さない
Safari で開く | app:Safari
CONF
	ok "設定ファイルを作成: $CONFIG"
}

set_default_browser() {
	echo
	info "macOS の確認ダイアログが出たら「\"${APP_NAME}\"を使用」をクリックしてください。"
	osascript -l JavaScript >/dev/null 2>&1 <<'JXA'
ObjC.import('CoreServices');
$.LSSetDefaultHandlerForURLScheme('http',  'com.local.accountpicker');
$.LSSetDefaultHandlerForURLScheme('https', 'com.local.accountpicker');
JXA
	sleep 2
	local handler
	handler=$(current_https_handler)
	if [ "$handler" = "$BUNDLE_ID" ]; then
		ok "デフォルトブラウザが ${APP_NAME} になりました。"
	else
		info "現在のデフォルト: $handler"
		info "ダイアログで許可しなかった場合や一覧から選び直す場合:"
		info "  システム設定 → デスクトップとDock → デフォルトのWebブラウザ"
		open "x-apple.systempreferences:com.apple.Desktop-Settings.extension" 2>/dev/null || true
	fi
}

# ------------------------------------------------------------
# インストール
# ------------------------------------------------------------
install_app() {
	require_macos
	echo
	echo "${BOLD}=== AccountPicker インストール ===${RESET}"
	echo "  macOS $(sw_vers -productVersion) / インストール先: $APP"
	echo

	mkdir -p "$APP_DIR"

	# 1) AppleScript をコンパイルして .app を生成
	TMPDIR_=$(mktemp -d) || die "一時フォルダを作成できません。"
	trap 'rm -rf "${TMPDIR_:-}"' EXIT
	applescript_source > "$TMPDIR_/main.applescript"

	rm -rf "$APP"
	if osacompile -o "$APP" "$TMPDIR_/main.applescript" 2> "$TMPDIR_/compile.log"; then
		ok "アプリ本体をコンパイル"
	else
		echo; cat "$TMPDIR_/compile.log"
		die "AppleScript のコンパイルに失敗しました（上のエラーをそのまま報告してください）。"
	fi

	# 2) http/https の受け口として登録できるよう Info.plist を設定
	local PB=/usr/libexec/PlistBuddy
	$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST" 2>/dev/null \
		|| $PB -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST" \
		|| die "CFBundleIdentifier の設定に失敗しました。"
	$PB -c 'Delete :CFBundleURLTypes' "$PLIST" 2>/dev/null
	$PB -c 'Add :CFBundleURLTypes array' "$PLIST" \
		&& $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLName string Web URL' "$PLIST" \
		&& $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$PLIST" \
		&& $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string http' "$PLIST" \
		&& $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string https' "$PLIST" \
		|| die "Info.plist への http/https 登録に失敗しました。"
	ok "Info.plist に http/https を登録"

	# 2b) デフォルトブラウザ一覧に載るために必要な「HTML書類を開ける」宣言
	$PB -c 'Delete :CFBundleDocumentTypes' "$PLIST" 2>/dev/null
	$PB -c 'Add :CFBundleDocumentTypes array' "$PLIST" \
		&& $PB -c 'Add :CFBundleDocumentTypes:0:CFBundleTypeName string HTML document' "$PLIST" \
		&& $PB -c 'Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer' "$PLIST" \
		&& $PB -c 'Add :CFBundleDocumentTypes:0:LSItemContentTypes array' "$PLIST" \
		&& $PB -c 'Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.html' "$PLIST" \
		&& $PB -c 'Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.xhtml' "$PLIST" \
		&& $PB -c 'Add :CFBundleDocumentTypes:0:LSItemContentTypes:2 string public.url' "$PLIST" \
		|| die "Info.plist への HTML 書類宣言の登録に失敗しました。"
	ok "デフォルトブラウザ一覧への掲載条件（HTML書類宣言）を登録"

	# 3) 署名と LaunchServices への登録
	xattr -dr com.apple.quarantine "$APP" 2>/dev/null
	codesign --force --sign - "$APP" >/dev/null 2>&1 || die "署名(codesign)に失敗しました。"
	ok "アプリを署名"
	"$LSREGISTER" -f "$APP" 2>/dev/null || die "LaunchServices への登録に失敗しました。"
	ok "macOS にブラウザとして登録"

	# 4) 設定ファイル
	write_default_config

	# 5) 検証
	echo
	echo "${BOLD}--- インストール検証 ---${RESET}"
	[ -d "$APP" ] && ok "アプリが存在する" || die "アプリが見つかりません。"
	plutil -lint "$PLIST" >/dev/null 2>&1 && ok "Info.plist が正しい形式" || die "Info.plist が壊れています。"
	$PB -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes' "$PLIST" 2>/dev/null | grep -q https \
		&& ok "https の受け口が有効" || die "https の登録が確認できません。"
	codesign --verify "$APP" 2>/dev/null && ok "署名が有効" || die "署名の検証に失敗しました。"

	# 6) 動作テスト
	echo
	read -r -p "動作テストをしますか？（選択ダイアログが開きます） [Y/n] " ans
	case "${ans:-Y}" in
		[Nn]*) ;;
		*)
			open -a "$APP" "https://docs.google.com/"
			echo
			read -r -p "ダイアログが表示され、選んだアカウントで開けましたか？ [Y/n] " ans2
			case "${ans2:-Y}" in
				[Nn]*) die "動作テスト失敗。--doctor の結果を報告してください。" ;;
				*) ok "動作テスト成功" ;;
			esac
			;;
	esac

	# 7) デフォルトブラウザに設定
	echo
	read -r -p "今すぐデフォルトブラウザに設定しますか？ [Y/n] " ans
	case "${ans:-Y}" in
		[Nn]*) info "後から設定する場合: システム設定 → デスクトップとDock → デフォルトのWebブラウザ" ;;
		*) set_default_browser ;;
	esac

	echo
	echo "${BOLD}=== 完了 ===${RESET}"
	echo "  アカウントの追加・変更 : open -e $CONFIG"
	echo "  プロファイル名の確認   : アプリをダブルクリック →「プロファイル一覧」"
	echo "  不調のときの診断       : bash \"$0\" --doctor"
	echo "  アンインストール       : bash \"$0\" --uninstall"
	echo
}

# ------------------------------------------------------------
# 診断
# ------------------------------------------------------------
doctor() {
	require_macos
	echo
	echo "${BOLD}=== AccountPicker 診断 ===${RESET}"
	echo "  macOS: $(sw_vers -productVersion)"
	echo

	[ -d "$APP" ] && ok "アプリ: $APP" || ng "アプリがありません → 再インストールしてください"

	if [ -f "$PLIST" ]; then
		if /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes' "$PLIST" 2>/dev/null | grep -q https; then
			ok "http/https の受け口: 登録済み"
		else
			ng "http/https の受け口: 未登録 → 再インストールしてください"
		fi
		if /usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:LSItemContentTypes' "$PLIST" 2>/dev/null | grep -q public.html; then
			ok "ブラウザ一覧への掲載条件（HTML書類宣言）: 登録済み"
		else
			ng "HTML書類宣言: 未登録 → 一覧に出ません。再インストールしてください"
		fi
		codesign --verify "$APP" 2>/dev/null && ok "署名: 有効" || ng "署名: 無効 → codesign --force --sign - \"$APP\""
	fi

	local handler
	handler=$(current_https_handler)
	if [ "$handler" = "$BUNDLE_ID" ]; then
		ok "デフォルトブラウザ: AccountPicker"
	else
		ng "デフォルトブラウザ: ${handler}（AccountPicker ではありません）"
	fi

	[ -d "/Applications/Google Chrome.app" ] && ok "Google Chrome: インストール済み" \
		|| ng "Google Chrome が /Applications にありません"

	if [ -f "$CONFIG" ]; then
		ok "設定ファイル: $CONFIG"
		echo
		echo "  --- 設定内容（コメント行除く） ---"
		grep -v '^\s*#' "$CONFIG" | grep -v '^\s*$' | sed 's/^/    /'
	else
		ng "設定ファイルがありません（初回起動時に自動生成されます）"
	fi

	echo
	echo "  --- Chrome プロファイル一覧 ---"
	osascript -l JavaScript 2>/dev/null <<'JXA' | sed 's/^/    /' || echo "    （取得できませんでした）"
ObjC.import('Foundation');
const p = $.NSHomeDirectory().js + '/Library/Application Support/Google/Chrome/Local State';
const s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null).js;
const info = JSON.parse(s).profile.info_cache;
Object.keys(info).sort().map(k => k + '  →  ' + (info[k].name || '') + '  ' + (info[k].user_name || '')).join('\n');
JXA
	echo
	echo "  問題が解決しない場合は、この画面の全文をコピーして報告してください。"
	echo
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall_app() {
	require_macos
	echo
	read -r -p "AccountPicker を削除します。よろしいですか？ [y/N] " ans
	case "${ans:-N}" in [Yy]*) ;; *) echo "中止しました。"; exit 0 ;; esac

	# 先にデフォルトブラウザを戻す（確認ダイアログが出ます）
	if [ "$(current_https_handler)" = "$BUNDLE_ID" ]; then
		local back="com.apple.Safari"
		[ -d "/Applications/Google Chrome.app" ] && back="com.google.Chrome"
		info "デフォルトブラウザを戻します（ダイアログで許可してください）"
		osascript -l JavaScript >/dev/null 2>&1 <<JXA
ObjC.import('CoreServices');
\$.LSSetDefaultHandlerForURLScheme('http',  '$back');
\$.LSSetDefaultHandlerForURLScheme('https', '$back');
JXA
		sleep 2
	fi

	[ -d "$APP" ] && "$LSREGISTER" -u "$APP" 2>/dev/null
	rm -rf "$APP" && ok "アプリを削除しました"

	read -r -p "設定ファイル（${CONFIG_DIR}）も削除しますか？ [y/N] " ans
	case "${ans:-N}" in [Yy]*) rm -rf "$CONFIG_DIR" && ok "設定を削除しました" ;; *) info "設定は残しました" ;; esac
	echo "完了。"
}

# ------------------------------------------------------------
# 入口
# ------------------------------------------------------------
case "${1:-}" in
	--doctor)            doctor ;;
	--uninstall)         uninstall_app ;;
	--print-applescript) applescript_source ;;   # アプリ本体のソースを表示（編集したい人向け）
	*)                   install_app ;;
esac
