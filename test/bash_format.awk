# bash_format.awk — Bash syntax highlighter + layout formatter + line breaker
# Usage: colors via -v _kw=... -v _str=... -v _reset=...  or -v dark=0/1 for defaults
#        awk -v dark=1 -f bash_format.awk <input>      (dark default)
#        awk -v _kw="$KW" -v _str="$STR" ... -f ...    (bash-provided)

BEGIN {
    # Only set defaults if not already provided via -v
    if (_reset == "") {
        if (dark == "false" || dark == "0") {
            _cmt = "\033[38;2;0;128;0m"
            _str = "\033[38;2;163;21;21m"
            _kw  = "\033[38;2;0;0;255m"
            _var = "\033[38;2;0;16;128m"
            _fn  = "\033[38;2;121;94;38m"
            _num = "\033[38;2;9;134;88m"
        } else {
            _cmt = "\033[38;2;106;153;85m"
            _str = "\033[38;2;206;145;120m"
            _kw  = "\033[38;2;86;156;214m"
            _var = "\033[38;2;156;220;254m"
            _fn  = "\033[38;2;220;220;170m"
            _num = "\033[38;2;181;206;168m"
        }
        _reset = "\033[0m"
    }

    kw["if"]=1; kw["then"]=1; kw["else"]=1; kw["elif"]=1; kw["fi"]=1
    kw["for"]=1; kw["while"]=1; kw["until"]=1; kw["do"]=1; kw["done"]=1
    kw["case"]=1; kw["esac"]=1; kw["in"]=1; kw["function"]=1
    kw["return"]=1; kw["exit"]=1; kw["export"]=1; kw["local"]=1
    kw["declare"]=1; kw["typeset"]=1; kw["readonly"]=1
    kw["eval"]=1; kw["source"]=1; kw["exec"]=1; kw["trap"]=1
    kw["set"]=1; kw["unset"]=1; kw["shift"]=1; kw["break"]=1; kw["continue"]=1
    kw["echo"]=1; kw["printf"]=1; kw["cd"]=1; kw["wait"]=1; kw["kill"]=1
    kw["test"]=1; kw["alias"]=1; kw["unalias"]=1
    kw["time"]=1; kw["type"]=1; kw["command"]=1; kw["builtin"]=1

    # Common external commands
    fn["ls"]=1; fn["cat"]=1; fn["cp"]=1; fn["mv"]=1; fn["rm"]=1
    fn["mkdir"]=1; fn["rmdir"]=1; fn["touch"]=1; fn["find"]=1
    fn["grep"]=1; fn["sed"]=1; fn["awk"]=1; fn["cut"]=1; fn["sort"]=1
    fn["uniq"]=1; fn["wc"]=1; fn["head"]=1; fn["tail"]=1; fn["diff"]=1
    fn["chmod"]=1; fn["chown"]=1; fn["ln"]=1; fn["stat"]=1; fn["du"]=1
    fn["df"]=1; fn["file"]=1; fn["basename"]=1; fn["dirname"]=1
    fn["ps"]=1; fn["killall"]=1; fn["sleep"]=1; fn["xargs"]=1
    fn["nohup"]=1; fn["pgrep"]=1; fn["pkill"]=1; fn["nice"]=1
    fn["curl"]=1; fn["wget"]=1; fn["ssh"]=1; fn["rsync"]=1
    fn["ping"]=1; fn["nc"]=1; fn["scp"]=1; fn["netstat"]=1
    fn["git"]=1; fn["make"]=1; fn["python"]=1; fn["python3"]=1
    fn["node"]=1; fn["npm"]=1; fn["pip"]=1; fn["pip3"]=1; fn["gcc"]=1
    fn["sudo"]=1; fn["date"]=1; fn["which"]=1; fn["env"]=1
    fn["tee"]=1; fn["tr"]=1; fn["uname"]=1; fn["whoami"]=1
    fn["id"]=1; fn["groups"]=1; fn["su"]=1; fn["mount"]=1
    fn["umount"]=1; fn["systemctl"]=1; fn["service"]=1
    fn["true"]=1; fn["false"]=1; fn["yes"]=1
    fn["more"]=1; fn["less"]=1; fn["vi"]=1; fn["vim"]=1; fn["nano"]=1
}

{
    line = $0; out = ""; state = 0; i = 1; len = length(line); _and_count = 0

    was_cont = (FNR > 1 && prev_cont)
    if (was_cont) { indent = prev_base + 3 }
    else          { indent = 0; prev_base = 0 }

    for (j = 0; j < indent; j++) out = out " "
    if (indent > 0) { sub(/^[[:space:]]+/, "", line); len = length(line) }

    if (line ~ /^[[:space:]]*#/) {
        m1 = line; sub(/[^[:space:]].*/, "", m1)
        m2 = line; sub(/^[[:space:]]*/, "", m2)
        out = out m1 _cmt m2 _reset
        printf "%s\n", out
        prev_cont = 0
        next
    }

    while (i <= len) {
        ch = substr(line, i, 1)

        # --- String boundaries ---
        if (state == 0 && (ch == "\"" || ch == "'")) {
            state = (ch == "\"" ? 1 : 2)
            out = out _str ch; i++; continue
        }
        if ((state == 1 && ch == "\"") || (state == 2 && ch == "'")) {
            out = out ch _reset; state = 0; i++; continue
        }
        if (state > 0) { out = out ch; i++; continue }

        # --- Semicolon line-break (state 0 only; NOT inside strings) ---
        if (ch == ";") {
            if (i < len && substr(line, i+1, 1) == ";") {
                # ;; case terminator — keep together, break after
                out = out ";;"
                i += 2
                while (i <= len && substr(line, i, 1) == " ") i++
                out = out "\n"
                continue
            } else {
                # Single ; — break line after
                out = out ";"
                i++
                while (i <= len && substr(line, i, 1) == " ") i++
                out = out "\n"
                continue
            }
        }

        # --- Variable: $VAR, ${VAR}, $@, $#, $?, $$, $!, $0-$9, $-
        # && line-break: 3rd+ && wraps with \ (state 0, not inside strings)
        if (ch == "&" && i < len && substr(line, i+1, 1) == "&") {
            _and_count++
            if (_and_count >= 3) {
                out = out " \\"; i += 2
                while (i <= len && substr(line, i, 1) == " ") i++
                out = out "\n    && "
                continue
            } else {
                out = out "&& "; i += 2
                while (i <= len && substr(line, i, 1) == " ") i++
                continue
            }
        }
        if (ch == "$") {
            rest = substr(line, i); vlen = 0
            if (rest ~ /^\$\{[^}]*\}/)      { vlen = index(rest, "}") + 1 }
            else if (rest ~ /^\$[A-Za-z_][A-Za-z0-9_]*/) {
                match(rest, /^\$[A-Za-z_][A-Za-z0-9_]*/); vlen = RLENGTH
            } else if (rest ~ /^\$[@#?*!0-9\$-]/) { vlen = 2 }
            if (vlen > 0) {
                out = out _var substr(line, i, vlen) _reset
                i += vlen; continue
            }
        }

        # --- Word ---
        if (ch ~ /[[:alnum:]_]/) {
            rest = substr(line, i)
            match(rest, /^[[:alnum:]_]+/)
            word = substr(rest, 1, RLENGTH)
            if (kw[word])      { out = out _kw word _reset }
            else if (fn[word]) { out = out _fn word _reset }
            else               { out = out word }
            i += RLENGTH; continue
        }

        out = out ch; i++
    }

    prev_cont = 0
    if (line ~ /\\[[:space:]]*$/)       { prev_cont = 1 }
    if (line ~ /[|&][|&]?[[:space:]]*$/) { prev_cont = 1 }
    if (prev_cont && !was_cont)         { prev_base = indent }
    if (line ~ /^[[:space:]]*[|&]/)     { prev_cont = 0; prev_base = 0 }

    printf "%s\n", out
}
