#!/usr/bin/env bash
#
# Bunch of grep functions to search log files
# Don't use complex one, so that each function can be easily copied and pasted
#
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
#
# TODO: tested on Mac only (eg: gsed, ggrep)
# brew install ripgrep      # for rg
# brew install grep         # 'grep' will install ggrep (may not need anymore)
# brew install gnu-sed      # for gsed
# brew install dateutils    # for dateconv
# brew install coreutils    # for gtac gdate
# brew install q
# pip install data_hacks    # for bar_chart.py
# curl https://raw.githubusercontent.com/hajimeo/samples/master/python/line_parser.py -o /usr/local/bin/line_parser.py
#

[ -n "$_DEBUG" ] && (set -x; set -e)

usage() {
    if [ -n "$1" ]; then
        _help "$1"
        return $?
    fi
    echo "HELP/USAGE:\
This script contains useful functions to search log files.

Required commands:
    brew install ripgrep      # for rg
    brew install grep         # for ggrep (may not need anymore)
    brew install gnu-sed      # for gsed
    brew install dateutils    # for dateconv
    brew install coreutils    # for gtac gdate
    brew install q
    pip install data_hacks    # for bar_chart.py

Setup:
    ln -s ${0} /usr/local/bin/log_search

HOW-TO: source (.), then use some function
    . log_search
    # Display usage/help of one function
    usage f_someFunctionName

    Examples:
    # Check what kind of caused by is most
    f_topCausedByExceptions ./yarn_application.log | tail -n 10

    # Check what kind of ERROR is most
    f_topErrors ./yarn_application.log | tail -n 10
Or
    ${BASH_SOURCE} -f log_file_path [-s start_date] [-e end_date] [-t log_type]
    NOTE:
      For start and end date, as using grep, may not return good result if you specify minutes or seconds.
      'log_type' currently accepts only 'ya' (yarn app log)

"
    echo "Available functions:"
    _list
}
### Public functions ###################################################################################################

function f_postgres_log() {
    local __doc__="grep (rg) postgresql log files"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-postgresql-*log*}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d"

    echo "### system is ready to|timeline|redo done at|archive recovery ###############################################"
    # log_line_prefix = %t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h (%l = Number of the log line for each session or process. No idea why -1)
    rg -z -N --no-filename -g "${_glob}" "^${_date_regex}.+( system is ready to|timeline|redo done at|archive recovery|FATAL:|ERROR:)" | grep -v 'no pg_hba.conf entry' | sort -n | uniq
    echo ' '
    echo "### Slow checkpoint complete ################################################################################"
    # With log_checkpoints = on
    rg -z -N --sort=path -g "${_glob}" "^${_date_regex}.+ checkpoint complete:.+(longest=[^0].+|average=[^0].+)"
}

function f_grep_multilines() {
    local __doc__="Multiline search with 'rg' dotall TODO: dot and brace can't be used in _str_in_1st_line"
    local _str_in_1st_line="$1"
    local _glob="${2:-"*.*log*"}"
    local _boundary_str="${3:-"^2\\d\\d\\d-\\d\\d-\\d\\d.\\d\\d:\\d\\d:\\d\\d"}"

    # NOTE: '\Z' to try matching the end of file returns 'unrecognized escape sequence'
    local _regex="${_str_in_1st_line}.+?(${_boundary_str}|\z)"
    echo "# regex:${_regex} -g '${_glob}'" >&2
    rg "${_regex}" \
        --multiline --multiline-dotall --no-line-number --no-filename -z \
        -g "${_glob}" -m 2000 --sort=path
    # not sure if rg sorts properly with --sort, so best effort (can not use ' | sort' as multi-lines)
}

function f_grep_logs() {
    local __doc__="Grep YYYY-MM-DD.hh:mm:ss.+<something>"
    local _str_in_1st_line="$1"
    local _glob="${2:-"*.*log*"}"
    local _exclude_warn_error="${3}"

    local _regex_1="^${_DATE_FORMAT}.\d\d:\d\d:\d\d.+(${_str_in_1st_line})"
    local _final_glob=""
    for _l in `rg "${_regex_1}" -l -g "${_glob}"`; do
        _final_glob="${_final_glob} -g ${_l}"
    done
    [ -z "${_final_glob}" ] && return

    local _regex="^${_DATE_FORMAT}.\d\d:\d\d:\d\d.+(${_str_in_1st_line}|\bWARN\b|\bERROR\b|\b.+?Exception\b|\b[Ff]ailed\b)"
    # It's a bit wasting resources...
    [[ "${_exclude_warn_error}" =~ ^[yY] ]] && _regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d.+(${_str_in_1st_line})"

    echo "# regex:${_regex} -g '${_glob}'" >&2
    rg -z "${_regex}" \
        --no-line-number --no-filename \
        ${_final_glob} | sort -n | uniq
}

function f_topCausedByExceptions() {
    local __doc__="List Caused By xxxxException (Requires rg)"
    local _path="$1"
    local _is_shorter="$2"
    local _regex="Caused by.+Exception"

    if [[ "$_is_shorter" =~ (^y|^Y) ]]; then
        _regex="Caused by.+?Exception"
    fi
    rg -z -N -o "$_regex" "$_path" | sort | uniq -c | sort -n
}

function f_topErrors() {
    local __doc__="List top ERRORs. NOTE: with _date_from and without may produce different result (ex: Caused by)"
    local _glob="${1:-"*.*log*"}"   # file path which rg accepts and NEEDS double-quotes
    local _date_regex="$2"   # ISO format datetime, but no seconds (eg: 2018-11-05 21:00)
    local _regex="$3"       # to overwrite default regex to detect ERRORs
    local _top_N="${4:-10}" # how many result to show

    if ! which rg &>/dev/null; then
        echo "'rg' is required (eg: brew install rg)" >&2
        return 101
    fi

    if [ -z "$_regex" ]; then
        _regex="\b(WARN|ERROR|SEVERE|FATAL|SHUTDOWN|Caused by|.+?Exception|FAILED)\b.+"
    fi

    if [ -n "${_date_regex}" ]; then
        _regex="^(${_date_regex}).+${_regex}"
    fi

    echo "# Regex = '${_regex}'"
    #rg -z -c -g "${_glob}" "${_regex}"
    rg -z -N --no-filename -g "${_glob}" -o "${_regex}" > /tmp/f_topErrors.$$.tmp

    # just for fun, drawing bar chart
    if [ -n "${_date_regex}" ] && which bar_chart.py &>/dev/null; then
        local _date_regex2="^[0-9-/]+ \d\d:\d"
        [ "`wc -l /tmp/f_topErrors.$$.tmp | awk '{print $1}'`" -lt 400 ] && _date_regex2="^[0-9-/]+ \d\d:\d\d"
        echo ' '
        rg -z --no-line-number --no-filename -o "${_date_regex2}" /tmp/f_topErrors.$$.tmp | sed 's/T/ /' | bar_chart.py
        echo " "
    fi

    cat "/tmp/f_topErrors.$$.tmp" | _replace_number | sort | uniq -c | sort -n | tail -n ${_top_N}
}

function f_listWarns() {
    local __doc__="List the counts of frequent warns and also errors"
    local _glob="${1:-"*.*log*"}"
    local _date_4_bar="${2:-"\\d\\d\\d\\d-\\d\\d-\\d\\d \\d\\d"}"
    local _top_N="${3:-40}"

    local _regex="\b(ERROR|FATAL|SEVERE|WARN|FAILED)\b"
    #rg -z -c -g "${_glob}" "${_regex}"
    rg -z -c -g "${_glob}" "^$_DATE_FORMAT.\d\d:\d\d:\d\d.+${_regex}"
    rg -z --no-line-number --no-filename -g "${_glob}" "^$_DATE_FORMAT.\d\d:\d\d:\d\d.+${_regex}" > /tmp/f_listWarns.$$.tmp

    # count by class name and ignoring only once or twice warns
    rg "${_regex}\s+[^ ]+\s+[^ ]+\s+[^ ]+\s+([^ ]+)" -o -r '$1 $2' /tmp/f_listWarns.$$.tmp | _replace_number | sort | uniq -c | sort -n | tail -n ${_top_N}
    echo " "
    rg -o "^${_date_4_bar}" /tmp/f_listWarns.$$.tmp | bar_chart.py
}

function f_topSlowLogs() {
    local __doc__="List top performance related log entries."
    local _date_regex="$1"
    local _glob="${2:-"*.*log*"}"
    local _regex="$3"
    local _not_hiding_number="$4"
    local _top_N="${5:-10}" # how many result to show

    if [ -z "$_regex" ]; then
        # case insensitive
        _regex="\b(slow|delay|delaying|latency|too many|not sufficient|lock held|took [1-9][0-9]+ ?ms|timeout|timed out)\b.+"
    fi
    if [ -n "${_date_regex}" ]; then
        _regex="^${_date_regex}.+${_regex}"
    fi

    echo "# Regex = '${_regex}'"
    rg -z -N --no-filename -g "${_glob}" -io "$_regex" > /tmp/f_topSlowLogs.$$.tmp
    #rg -z -c -g "${_glob}" -wio "${_regex}"
    if [[ "$_not_hiding_number" =~ (^y|^Y) ]]; then
        cat /tmp/f_topSlowLogs.$$.tmp
    else
        # ([0-9]){2,4} didn't work also (my note) sed doesn't support \d
        cat /tmp/f_topSlowLogs.$$.tmp | _replace_number
    fi | sort | uniq -c | sort -n | tail -n ${_top_N}
}

function f_appLogFindAppMaster() {
    local __doc__="After yarn_app_logs_splitter, find which node was AppMaster. TODO: currently only MR and not showing host"
    local _splitted_dir="${1:-.}"
    rg -l 'Created MRAppMaster' "${_splitted_dir%/}/*.syslog"
}

function f_appLogContainersAndHosts() {
    local __doc__="List containers ID and host (from YARN app log)"
    local _path="$1"
    local _sort_by_host="$2"

    if [[ "$_sort_by_host" =~ (^y|^Y) ]]; then
        _grep "^Container: container_" "$_path" | sort -k4 | uniq
    else
        _grep "^Container: container_" "$_path" | sort | uniq
    fi
}

function f_appLogContainerCountPerHost() {
    local __doc__="Count container per host (from YARN app log)"
    local _path="$1"
    local _sort_by_host="$2"

    if [[ "$_sort_by_host" =~ (^y|^Y) ]]; then
        f_appLogContainersAndHosts "$1" | awk '{print $4}' | sort | uniq -c
    else
        f_appLogContainersAndHosts "$1" | awk '{print $4}' | sort | uniq -c | sort -n
    fi
}

function f_appLogJobCounters() {
    local __doc__="List the Job Final counters (Tez only?) (from YARN app log)"
    local _path="$1"
    local _line=""
    local _regex="(Final Counters for [^ :]+)[^\[]+(\[.+$)"

    rg --no-line-number --no-filename -z -o "Final Counters for .+$" "$_path" | while read -r _line ; do
        if [[ "$_line" =~ ${_regex} ]]; then
            echo "# ${BASH_REMATCH[1]}"
            # TODO: not clean enough. eg: [['File System Counters HDFS_BYTES_READ=1469456609',
            echo "${BASH_REMATCH[2]}" | _sed -r 's/\[([^"\[])/\["\1/g' | _sed -r 's/([^"])\]/\1"\]/g' | _sed -r 's/([^"]), ([^"])/\1", "\2/g' | _sed -r 's/\]\[/\], \[/g' | python -m json.tool
            echo ""
        fi
    done
}

function f_appLogJobExports() {
    local __doc__="List exports in the job (from YARN app log)"
    local _path="$1"
    local _regex="^export "

    egrep "$_regex" "$_path" | sort | uniq -c
}

function f_appLogFindFirstSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was started first."
    local _dir_path="${1-.}"
    local _num="${2-10}"

    ( find "${_dir_path%/}" -name "*.syslog" | xargs -I {} bash -c "_grep -oHP '^${_DATE_FORMAT} \d\d:\d\d:\d\d' -m 1 {}" | awk -F ':' '{print $2":"$3":"$4" "$1}' ) | sort -n | head -n $_num
}

function f_appLogFindLastSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was ended in the last. gtac/tac is required"
    local _dir_path="${1-.}"
    local _num="${2-10}"
    local _regex="${3}"

    if [ -n "$_regex" ]; then
        ( for _f in `_grep -l "$_regex" ${_dir_path%/}/*.syslog`; do _dt="`_tac $_f | _grep -oP "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    else
        ( for _f in `find "${_dir_path%/}" -name "*.syslog"`; do _dt="`_tac $_f | _grep -oP "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    fi
}

function f_appLogSplit() {
    local __doc__="(deprecated: no longer works with Ambari 2.7.x / HDP 2.6.x) Split YARN App log with yarn_app_logs_splitter.py"
    local _app_log="$1"

    local _out_dir="containers_`basename $_app_log .log`"
    # Assuming yarn_app_logs_splitter.py is in the following location
    local _script_path="$(dirname "$_SCRIPT_DIR")/misc/yarn_app_logs_splitter.py"
    if [ ! -s "$_script_path" ]; then
        echo "$_script_path does not exist. Downloading..."
        if [ ! -d "$(dirname "${_script_path}")" ]; then
            mkdir -p "$(dirname "${_script_path}")" || return $?
        fi
        curl -so "${_script_path}" https://raw.githubusercontent.com/hajimeo/samples/master/misc/yarn_app_logs_splitter.py || return $?
    fi
    if [ ! -r "$_app_log" ]; then
        echo "$_app_log is not readable"
        return 1
    fi
    #_grep -Fv "***********************************************************************" $_app_log > /tmp/${_app_log}.tmp
    python "$_script_path" --container-log-dir $_out_dir --app-log "$_app_log"
}

function f_appLogCSplit() {
    local __doc__="Split YARN App log with csplit/gcsplit"
    local _app_log="$1"
    local _no_rename="$2"

    local _out_dir="`basename $_app_log .log`_containers"
    if [ ! -r "$_app_log" ]; then
        echo "$_app_log is not readable"
        return 1
    fi

    if [ ! -d $_out_dir ]; then
        mkdir -p $_out_dir || return $?
    fi

    _csplit -z -f $_out_dir/lineNo_ $_app_log "/^Container: container_/" '{*}' || return $?
    if [[ "${_no_rename}" =~ ^(y|Y) ]]; then
        echo "Not renaming 'lineNo_*' files."
    else
        _appLogCSplit_rename "." "${_out_dir}"
    fi
}

function _appLogCSplit_rename() {
    local _in_dir="${1:-.}"
    local _out_dir="${2:-.}"

    local _new_filename=""
    local _type=""
    # -bash: /bin/ls: Argument list too long, also i think xargs can't use eval, also there is command length limit!
    #find $_out_dir -type f -name 'lineNo_*' -print0 | xargs -P 3 -0 -n1 -I {} bash -c "cd $PWD; _f={};_new_filepath=\"\`head -n 1 \${_f} | grep -oE \"container_.+\" | tr ' ' '_'\`\" && mv \${_f} \"${_out_dir%/}/\${_new_filepath}.out\""
    find ${_in_dir} -type f -name 'lineNo_*' -print > /tmp/f_appLogCSplit.out
    for _f in `cat f_appLogCSplit.out`; do
        _new_filename="`head -n 1 ${_f} | grep -oE "container_[a-z0-9_]+"`"
        _type="`grep -m 1 '^LogType:' ${_f} | cut -d ':' -f2`"
        if [ -n "${_new_filename}" ]; then
            if [[ "${_type}" =~ ^.+\.dot$ ]]; then
                rg '^digraph.+\}' --multiline --multiline-dotall --no-filename --no-line-number ${_f} > "${_out_dir%/}/${_new_filename}.${_type}" && rm -f "${_f}"
            else
                # .${_type} is always .stderr but file contains all types for the container, so using .log
                mv -v -i ${_f} "${_out_dir%/}/${_new_filename}.log"
            fi
        fi
    done
}

function f_appLogSwimlane() {
    local __doc__="TODO: use swimlane (but broken?)"
    local _app_log="$1"

    local _out_name="`basename $_app_log .log`.svg"
    local _tmp_name="`basename $_app_log .log`.tmp"
    local _script_path="$(dirname "$_SCRIPT_DIR")/misc/swimlane.py"
    _grep 'HISTORY' $_app_log > ./$_tmp_name
    if [ ! -s "$_tmp_name" ]; then
        echo "$_tmp_name is empty."
        return 1
    fi
    if [ ! -s "$_script_path" ]; then
        echo "$_script_path does not exist"
        return 1
    fi
    python "$_script_path" -o $_out_name $_tmp_name
}

function f_appLogHISTORY() {
    local __doc__="grep keyword from [HISTORY] line"
    local _app_log="$1"
    local _keyword="${2-"timeTaken"}"   # maxTaskDuration

    local _hist_file="/tmp/`basename $_app_log .log`.hist"
    [ ! -s "${_hist_file}" ] && rg -z --no-line-number --no-filename -o '\[HISTORY\].+' $_app_log > $_hist_file || return $?
    [ -n "${_keyword}" ] && rg --no-filename --no-line-number -o "vertexName=([^,]+).+vertexId=([^,]+).+${_keyword}=([^,]+)" -r $'${2}\t${1}\t${3}' $_hist_file | sort -t$'\t' -n -k3

    # TODO: rg '</PERFLOG.+duration=\d{7}+' --no-filename | sort
}

function f_appLogTransition() {
    local __doc__="grep transitioned"
    # f_appLogTransition "*" "" | bar
    # f_appLogTransition "*" "RUNNING" | sort -t $'\t' -k2  # sort by vertexName
    # rg 'VertexName: Reducer 20'
    local _app_log="$1"
    local _keyword="${2-"RUNNING"}"
    # vertex_[0-9_]+
    rg --no-filename --no-line-number -o "^(${_DATE_FORMAT}.\d\d:\d\d:\d\d).+(\[[^]]+\]) (transitioned from.+${_keyword}.+)" -r $'${1}\t${2}\t${3}' | sort | uniq
}

function f_hdfsAuditLogCountPerTime() {
    local __doc__="Count a log file (eg.: HDFS audit) per 10 minutes"
    local _path="$1"
    local _datetime_regex="$2"

    if [ -z "$_datetime_regex" ]; then
        _datetime_regex="^${_DATE_FORMAT} \d\d:\d"
    fi

    if ! which bar_chart.py &>/dev/null; then
        echo "### bar_chart.py is missing..."
        echo "# sudo -H python -mpip install matplotlib"
        echo "# sudo -H pip3 install data_hacks"
        local _cmd="uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    _grep -oP "$_datetime_regex" $_path | $_cmd
}

function f_hdfsAuditLogCountPerCommand() {
    local __doc__="Count HDFS audit per command for some period"
    local _path="$1"
    local _datetime_regex="$2"

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="sort | uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    # TODO: not sure if sed regex is good (seems to work, Mac sed / gsed doesn't like +?)、Also sed doen't support ¥d
    if [ ! -z "$_datetime_regex" ]; then
        _sed -n "s@\($_datetime_regex\).*\(cmd=[^ ]*\).*src=.*\$@\1,\2@p" $_path | $_cmd
    else
        _sed -n 's:^.*\(cmd=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_hdfsAuditLogCountPerUser() {
    local __doc__="Count HDFS audit per user for some period"
    local _path="$1"
    local _per_method="$2"
    local _datetime_regex="$3"

    if [ ! -z "$_datetime_regex" ]; then
        _grep -P "$_datetime_regex" $_path > /tmp/f_hdfs_audit_count_per_user_$$.tmp
        _path="/tmp/f_hdfs_audit_count_per_user_$$.tmp"
    fi

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="sort | uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    # TODO: not sure if sed regex is good (seems to work, Mac sed / gsed doesn't like +?)
    if [[ "$_per_method" =~ (^y|^Y) ]]; then
        _sed -n 's:^.*\(ugi=[^ ]*\) .*\(cmd=[^ ]*\).*src=.*$:\1,\2:p' $_path | $_cmd
    else
        _sed -n 's:^.*\(ugi=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_listPerflogEnd() {
    local __doc__="Hive: _grep </PERFLOG ...> to see duration"
    local _path="$1"
    local _sort_by_duration="$2"

    if [[ "$_sort_by_duration" =~ (^y|^Y) ]]; then
        # expecting 5th one is duration after removing start and end time
        #egrep -wo '</PERFLOG .+>' "$_path" | sort -t'=' -k5n
        # removing start and end so that we can easily compare two PERFLOG outputs
        rg -z -wo '</PERFLOG .+>' $_path | _sed -r "s/ (start|end)=[0-9]+//g" | sort -t'=' -k3n
    else
        # sorting with start time
        rg -z -wo '</PERFLOG .+>' $_path | sort -t'=' -k3n
    fi
}

function f_getPerflog() {
    local __doc__="Hive: Get lines between PERFLOG method=xxxxx"
    local _path="$1"
    local _approx_datetime="$2"
    local _thread_id="$3"
    local _method="${4-compile}"

    _getAfterFirstMatch "$_path" "^${_approx_datetime}.+ Thread-${_thread_id}\]: .+<PERFLOG method=${_method} " "Thread-${_thread_id}\]: .+<\/PERFLOG method=${_method} " | _grep -vP ": Thread-(?!${_thread_id})\]"
}

function f_list_start_end(){
    local __doc__="Output start time, end time, difference(sec), (filesize) from *multiple* log files"
    local _glob="${1}"
    local _date_regex="${2:-${_DATE_FORMAT}.\d\d:\d\d:\d\d}"
    local _sort="${3:-2}"
    # If no file(s) given, check current working directory
    if [ -n "${_glob}" ]; then
        _files="`find . -type f -name "${_glob}" -print`"
    else
        local _files="`ls -1`"
    fi
    for _f in `echo ${_files}`; do f_start_end_time_with_diff $_f "^${_date_regex}"; done | sort -t$'\t' -k${_sort} | column -t -s$'\t'
}

function f_start_end_time_with_diff(){
    local __doc__="Output start time, end time, difference(sec), (filesize) from a log file"
    #eg: for _f in \`ls\`; do f_start_end_time_with_diff \$_f \"^${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d\d\d\"; done | sort -t$'\\t' -k2)
    local _log="$1"
    local _date_regex="${2}"
    [ -z "$_date_regex" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d"

    local _start_date=`rg -z -N -om1 "^$_date_regex" ${_log} | sed 's/T/ /'` || return $?
    local _extension="${_log##*.}"
    if [ "${_extension}" = 'gz' ]; then
        local _end_date=`gunzip -c ${_log} | _tac | rg -N -om1 "^$_date_regex" | sed 's/T/ /'` || return $?
    else
        local _end_date=`_tac ${_log} | rg -z -N -om1 "^$_date_regex" | sed 's/T/ /'` || return $?
    fi
    local _start_int=`_date2int "${_start_date}"`
    local _end_int=`_date2int "${_end_date}"`
    local _diff=$(( $_end_int - $_start_int ))
    # Filename, start datetime, enddatetime, difference, (filesize)
    echo -e "`basename ${_log}`\t${_start_date}\t${_end_date}\t${_diff} s\t$((`wc -c <${_log}` / 1024)) KB"
}

function f_split_strace() {
    local __doc__="Split a strace output, which didn't use -ff, per PID. As this function may take time, it should be safe to cancel at any time, and re-run later"
    local _strace_file="$1"
    local _save_dir="${2-./}"
    local _reverse="$3"

    local _cat="cat"
    if [[ "${_reverse}" =~ (^y|^Y) ]]; then
        which tac &>/dev/null && _cat="tac"
        which gtac &>/dev/null && _cat="gtac"
    fi

    [ ! -d "${_save_dir%/}" ] && ( mkdir -p "${_save_dir%/}" || return $? )
    if [ ! -s "${_save_dir%/}/_pid_list.tmp" ]; then
        awk '{print $1}' "${_strace_file}" | sort -n | uniq > "${_save_dir%/}/_pid_list.tmp"
    else
        echo "${_save_dir%/}/_pid_list.tmp exists. Reusing..." 1>&2
    fi

    for _p in `${_cat} "${_save_dir%/}/_pid_list.tmp"`
    do
        if [ -s "${_save_dir%/}/${_p}.out" ]; then
            if [[ "${_reverse}" =~ (^y|^Y) ]]; then
                echo "${_save_dir%/}/${_p}.out exists. As reverse mode, exiting..." 1>&2
                return
            fi
            echo "${_save_dir%/}/${_p}.out exists. skipping..." 1>&2
            continue
        fi
        _grep "^${_p} " "${_strace_file}" > "${_save_dir%/}/.${_p}.out" && mv -f "${_save_dir%/}/.${_p}.out" "${_save_dir%/}/${_p}.out"
    done
}


function f_git_search() {
    local __doc__="Grep git comments to find matching branch or tag"
    local _search="$1"
    local _git_dir="$2"
    local _is_fetching="$3"
    local _is_showing_grep_result="$4"

    if [ -d "$_git_dir" ]; then
       cd "$_git_dir"
    fi

    if [[ "$_is_fetching" =~ (^y|^Y) ]]; then
        git fetch
    fi

    local _grep_result="`git log --all --grep "$_search"`"
    if [[ "$_is_showing_grep_result" =~ (^y|^Y) ]]; then
        echo "$_grep_result"
    fi

    local _commits_only="`echo "$_grep_result" | _grep ^commit | cut -d ' ' -f 2`"

    echo "# Searching branches ...."
    for c in $_commits_only; do git branch -r --contains $c; done | sort
    echo "# Searching tags ...."
    for c in $_commits_only; do git tag --contains $c; done | sort
}

function f_os_checklist() {
    local __doc__="Outputs some OS kernel parameters (and compare with working one)"
    local _conf="${1-./}"

    #cat /sys/kernel/mm/transparent_hugepage/enabled
    #cat /sys/kernel/mm/transparent_hugepage/defrag

    # 1. check "sysctl -a" output
    # Ref: http://www.tweaked.io/guide/kernel/ https://github.com/t3rmin4t0r/notes/wiki/Hadoop-Tuning-notes
    # So far, removing net.ipv4.conf.*.forwarding
    local _props="fs.file-nr vm.zone_reclaim_mode vm.overcommit_memory vm.swappiness vm.dirty_ratio vm.dirty_background_ratio kernel.shmmax kernel.shmall kernel.sem kernel.msgmni kernel.sysrq vm.oom_dump_tasks net.core.somaxconn net.core.netdev_max_backlog net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.ipv4.ip_local_port_range net.ipv4.tcp_mtu_probing net.ipv4.tcp_fin_timeout net.ipv4.tcp_syncookies net.ipv4.conf.default.accept_source_route net.ipv4.tcp_tw_recycle net.ipv4.tcp_max_syn_backlog net.ipv4.conf.all.arp_filter"

    _search_properties "${_conf%/}" "${_props}"
}

function f_hdfs_checklist() {
    local __doc__="Store HDFS config checklist in this function"
    local _conf="${1-./}"

    # 1. check the following properties' values
    local _props="dfs.namenode.audit.log.async dfs.namenode.servicerpc-address dfs.namenode.handler.count dfs.namenode.service.handler.count dfs.namenode.lifeline.rpc-address ipc.[0-9]+.backoff.enable ipc.[0-9]+.callqueue.impl dfs.namenode.name.dir< dfs.journalnode.edits.dir dfs.namenode.accesstime.precision"

    _search_properties "${_conf%/}/*-site.xml" "${_props}" "Y"

    # 2. Check log4j config for performance
    _grep -P '^log4j\..+\.(BlockStateChange|StateChange)' ${_conf%/}/log4j.properties
}

function f_hive_checklist() {
    local __doc__="Store Hive config checklist in this function"
    local _conf="${1-./}"   # set / set -v output or hive-site.xml
    local _others="$2"      # check HDFS, YARN, MR2 configs if 'y'

    # 1. check the following properties' values
    # _grep -ohP '\(property\(.+$' * | cut -d '"' -f 2 | tr '\n' ' '

    echo "# Hive config check" >&2
    local _props="hive.auto.convert.join hive.merge.mapfiles hive.merge.mapredfiles hive.exec.compress.intermediate hive.exec.compress.output datanucleus.cache.level2.type hive.default.fileformat.managed hive.default.fileformat fs.hdfs.impl.disable.cache fs.file.impl.disable.cache hive.cbo.enable hive.compute.query.using.stats hive.stats.fetch.column.stats hive.stats.fetch.partition.stats hive.execution.engine datanucleus.fixedDatastore hive.exim.strict.repl.tables datanucleus.autoCreateSchema hive.exec.parallel hive.plan.serialization.format hive.server2.tez.initialize.default.sessions hive.vectorized.execution.enabled hive.vectorized.execution.reduce.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Tez config check" >&2
    _props="tez.am.am-rm.heartbeat.interval-ms.max tez.runtime.transfer.data-via-events.enabled tez.session.am.dag.submit.timeout.secs tez.am.container.reuse.enabled tez.runtime.io.sort.mb tez.session.client.timeout.secs tez.runtime.shuffle.memory-to-memory.enable tez.runtime.task.input.post-merge.buffer.percent tez.am.container.session.delay-allocation-millis tez.session.am.dag.submit.timeout.secs tez.runtime.shuffle.fetch.buffer.percent tez.task.am.heartbeat.interval-ms.max tez.task.am.heartbeat.counter.interval-ms.max tez.task.get-task.sleep.interval-ms.max tez.task.scale.memory.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Hive extra config check" >&2
    _props="hive.metastore.client.connect.retry.delay hive.metastore.client.connect.retry.delay hive.metastore.failure.retries hive\..*aux.jars.path hive.server2.async.exec.threads hive\.server2\..*\.threads hive.tez.java.opts hive.server2.idle.session.check.operation hive.server2.session.check.interval hive.server2.idle.session.timeout hive.server2.idle.operation.timeout tez.session.am.dag.submit.timeout.secs tez.yarn.ats.event.flush.timeout.millis hive.llap.* fs.permissions.umask-mode hive.optimize.reducededuplication"
    _search_properties "${_conf%/}" "${_props}"

    # 2. Extra properties from set output
    echo -e "\n# hadoop common (mainly from core-site.xml and set -v required)" >&2
    _props="hadoop\.proxyuser\..* hadoop\.ssl\..* hadoop\.http\.authentication\..* ipc\.client\..*"
    _search_properties "${_conf%/}" "${_props}"

    if [[ "$_others" =~ (^y|^Y) ]]; then
        echo -e "\n# HDFS config check" >&2
        _props="hdfs.audit.logger dfs.block.access.token.enable dfs.blocksize dfs.namenode.checkpoint.period dfs.datanode.failed.volumes.tolerated dfs.datanode.max.transfer.threads dfs.permissions.enabled hadoop.security.group.mapping fs.defaultFS dfs.namenode.accesstime.precision dfs.ha.automatic-failover.enabled dfs.namenode.checkpoint.txns dfs.namenode.stale.datanode.interval dfs.namenode.name.dir dfs.namenode.handler.count dfs.namenode.metrics.logger.period.seconds dfs.namenode.name.dir dfs.namenode.top.enabled fs.protected.directories dfs.replication dfs.namenode.name.dir.restore dfs.namenode.safemode.threshold-pct dfs.namenode.avoid.read.stale.datanode dfs.namenode.avoid.write.stale.datanode dfs.replication dfs.client.block.write.replace-datanode-on-failure.enable dfs.client.block.write.replace-datanode-on-failure.policy dfs.client.block.write.replace-datanode-on-failure.best-effort dfs.datanode.du.reserved hadoop.security.logger dfs.client.read.shortcircuit dfs.domain.socket.path fs.trash.interval ha.zookeeper.acl ha.health-monitor.rpc-timeout.ms dfs.namenode.replication.work.multiplier.per.iteration"
        _search_properties "${_conf%/}" "${_props}"

        echo -e "\n# YARN config check" >&2
        _props="yarn.timeline-service.generic-application-history.save-non-am-container-meta-info yarn.timeline-service.enabled hadoop.security.authentication yarn.timeline-service.http-authentication.type yarn.timeline-service.store-class yarn.timeline-service.ttl-enable yarn.timeline-service.ttl-ms yarn.acl.enable yarn.log-aggregation-enable yarn.nodemanager.recovery.enabled yarn.resourcemanager.recovery.enabled yarn.resourcemanager.work-preserving-recovery.enabled yarn.nodemanager.local-dirs yarn.nodemanager.log-dirs yarn.nodemanager.resource.cpu-vcores yarn.nodemanager.vmem-pmem-ratio"
        _search_properties "${_conf%/}" "${_props}"

        echo -e "\n# MR config check" >&2
        _props="mapreduce.map.output.compress mapreduce.output.fileoutputformat.compress io.sort.factor mapreduce.task.io.sort.mb mapreduce.map.sort.spill.percent mapreduce.map.speculative mapreduce.input.fileinputformat.split.maxsize mapreduce.input.fileinputformat.split.minsize mapreduce.reduce.shuffle.parallelcopies mapreduce.reduce.speculative mapreduce.job.reduce.slowstart.completedmaps mapreduce.tasktracker.group"
        _search_properties "${_conf%/}" "${_props}"
    fi

    # 3. Extra properties from set output
    if [ -f "$_conf" ]; then
        echo -e "\n# System:java" >&2
        # |system:java\.class\.path
        _grep -P '^(env:HOSTNAME|env:HADOOP_HEAPSIZE|env:HADOOP_CLIENT_OPTS|system:hdp\.version|system:java\.home|system:java\.vm\.*|system:java\.io\.tmpdir|system:os\.version|system:user\.timezone)=' "$_conf"
    fi
}

_COMMON_QUERIE_UPDATES="UPDATE users SET user_password='538916f8943ec225d97a9a86a2c6ec0818c1cd400e09e03b660fdaaec4af29ddbb6f2b1033b81b00' WHERE user_name='admin' and user_type='LOCAL';"
_COMMON_QUERIE_SELECTS="select * from metainfo where metainfo_key = 'version';select repo_version_id, stack_id, display_name, repo_type, substring(repositories, 1, 500) from repo_version order by repo_version_id desc limit 5;SELECT * FROM clusters WHERE security_type = 'KERBEROS';"
function f_load_ambaridb_to_postgres() {
    local __doc__="Load ambari DB sql file into Mac's (locals) PostgreSQL DB"
    local _sql_file="$1"
    local _missing_tables_sql="$2"
    local _sudo_user="${3-$USER}"
    local _ambari_pwd="${4-bigdata}"

    # If a few tables are missing, need missing tables' schema
    # pg_dump -Uambari -h `hostname -f` ambari -s -t alert_history -t host_role_command -t execution_command -t request > ambari_missing_table_ddl.sql

    if ! sudo -u ${_sudo_user} -i psql template1 -c '\l+'; then
        echo "Connecting to local postgresql failed. Is PostgreSQL running?"
        echo "pg_ctl -D /usr/local/var/postgres -l ~/postgresql.log restart"
        return 1
    fi
    sleep 3q

    #echo "sudo -iu ${_sudo_user} psql template1 -c 'DROP DATABASE ambari;'"
    if ! sudo -iu ${_sudo_user} psql template1 -c 'ALTER DATABASE ambari RENAME TO ambari_'$(date +"%Y%m%d%H%M%S") ; then
        sudo -iu ${_sudo_user} psql template1 -c "select pid, usename, application_name, client_addr, client_port, waiting, state, query_start, query, xact_start from pg_stat_activity where datname='ambari'"
        return 1
    fi
    sudo -iu ${_sudo_user} psql template1 -c 'CREATE DATABASE ambari;'
    sudo -iu ${_sudo_user} psql template1 -c "CREATE USER ambari WITH LOGIN PASSWORD '${_ambari_pwd}';"
    sudo -iu ${_sudo_user} psql template1 -c 'GRANT ALL PRIVILEGES ON DATABASE ambari TO ambari;'

    export PGPASSWORD="${_ambari_pwd}"
    psql -Uambari -h `hostname -f` ambari -c 'CREATE SCHEMA ambari;ALTER SCHEMA ambari OWNER TO ambari;'

    # TODO: may need to replace the schema if not 'ambari'
    #_sed -i'.bak' -r 's/\b(custom_schema|custom_owner)\b/ambari/g' ambari.sql

    # It's OK to see relation error for index (TODO: upgrade table may fail)
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` ambari < ${_sql_file}
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` -c "${_COMMON_QUERIE_UPDATES}"
    psql -Uambari -h `hostname -f` -c "${_COMMON_QUERIE_SELECTS}"

    echo "psql -Uambari -h `hostname -f` -xc \"UPDATE clusters SET security_type = 'NONE' WHERE provisioning_state = 'INSTALLED' and security_type = 'KERBEROS';\""
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/services/KERBEROS"
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/artifacts/kerberos_descriptor"
    unset PGPASSWORD
}

function f_load_ambaridb_to_mysql() {
    local __doc__="Load ambari DB sql file into Mac's (locals) MySQL DB"
    local _sql_file="$1"
    local _missing_tables_sql="$2"
    local _sudo_user="${3-$USER}"
    local _ambari_pwd="${4-bigdata}"

    # If a few tables are missing, need missing tables' schema
    # pg_dump -Uambari -h `hostname -f` ambari -s -t alert_history -t host_role_command -t execution_command -t request > ambari_missing_table_ddl.sql

    if ! mysql -u root -e 'show databases'; then
        echo "Connecting to local MySQL failed. Is MySQL running?"
        echo "brew services start mysql"
        return 1
    fi

    mysql -u root -e "CREATE USER 'ambari'@'%' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'%';
CREATE USER 'ambari'@'localhost' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'localhost';
CREATE USER 'ambari'@'`hostname -f`' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'`hostname -f`';
FLUSH PRIVILEGES;"

    if ! mysql -uambari -p${_ambari_pwd} -h `hostname -f` -e 'create database ambari'; then
        echo "Please drop the database first as renaming DB on MySQL is hard"
        echo "mysql -uambari -p${_ambari_pwd} -h `hostname -f` -e 'DROP DATABASE ambari;'"
        return
    fi

    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari < "${_sql_file}"

    # TODO: _missing_tables_sql
    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e "${_COMMON_QUERIE_UPDATES}"
    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e "${_COMMON_QUERIE_SELECTS}"

    echo "mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e \"UPDATE clusters SET security_type = 'NONE' WHERE provisioning_state = 'INSTALLED' and security_type = 'KERBEROS';\""
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/services/KERBEROS"
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/artifacts/kerberos_descriptor"
}

function f_gc_before_after_check() {
    local __doc__="TODO: add PrintClassHistogramBeforeFullGC, and parse log to find which objects are increasing"
    return
    # TODO: _grep -F '#instances' -A 20 solr_gc.log | _grep -E -- '----------------|org.apache'
    export JAVA_GC_LOG_DIR="/some/location"
    export JAVA_GC_OPTS="-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JAVA_GC_LOG_DIR%/}/ \
    -XX:+PrintClassHistogramBeforeFullGC -XX:+PrintClassHistogramAfterFullGC \
    -XX:+TraceClassLoading -XX:+TraceClassUnloading \
    -verbose:gc -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps \
    -Xloggc:${JAVA_GC_LOG_DIR}/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1024k"
}

function f_validate_siro_ini() {
    local __doc__="TODO: Read shiro config file and, at least, generate ldapsarch command"
    return
}

function f_count_lines() {
    local __doc__="Count lines between _search_regex of periodic.log"
    local _file="$1"
    local _search_regex="${2:-"^20\\d\\d-\\d\\d-\\d\\d .+Periodic stack trace"}"

    [ -z "${_file}" ] && _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    [ ! -s "${_file}" ] && return

    local _ext="${_file##*.}"
    if [[ "${_ext}" =~ gz ]]; then
        local _line_num=`gunzip -c ${_file} | wc -l | tr -d '[:space:]'`
        rg -n --no-filename -z "${_search_regex}" ${_file} | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    else
        local _line_num=`wc -l <${_file} | tr -d '[:space:]'`
        rg -n --no-filename -z "${_search_regex}" ${_file} | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    fi
}

function f_count_threads() {
    local __doc__="Grep periodic log and count threads of periodic.log"
    local _file="$1"
    local _tail_n="${2-10}"
    [ -z "${_file}" ] &&  _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    [ ! -s "${_file}" ] && return

    if [ -n "${_tail_n}" ]; then
        rg -z -N -o '^"([^"]+)"' -r '$1' "${_file}" | _sed -r 's/-[0-9]+$//g' | sort | uniq -c | sort -n | tail -n ${_tail_n}
    else
        rg -z -N -o '^"([^"]+)"' -r '$1' "${_file}" | sort | uniq
    fi
}

function f_count_threads_per_dump() {
    local __doc__="Split periodic (thread dump) log and count threads per dump"
    local _file="$1"
    local _search="${2:-"- Periodic stack trace .:"}"

    [ -z "${_file}" ] &&  _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    local _tmp_dir="/tmp/tdumps"
    local _prefix="periodic_"
    _file="$(realpath "${_file}")"

    mkdir ${_tmp_dir} &>/dev/null
    cd ${_tmp_dir} || return $?

    local _ext="${_file##*.}"
    if [[ "${_ext}" =~ gz ]]; then
        _csplit -f "${_prefix}" <(gunzip -c ${_file}) "/${_search}/" '{*}'
    else
        _csplit -f "${_prefix}" ${_file} "/${_search}/" '{*}'
    fi

    if [ $? -ne 0 ]; then
        cd -
        return 1
    fi

    for _f in `ls -1 ${_prefix}*`; do
        head -n 1 $_f
        # NOTE: currently excluding thread which occurrence is only 1.
        rg '^"([^"]+)"' -o -r '$1' $_f | _sed 's/[0-9]\+/_/g' | sort | uniq -c | grep -vE '^ +1 '
        echo '--'
    done
    cd -
}

function f_request2csv() {
    local __doc__="Convert a jetty request log to a csv file"
    local _request_file="$1"
    local _csv="$2"
    if [ -z "${_csv}" ]; then
        _csv="$(basename ${_request_file} .log).csv"
    fi
    # NOTE: check jetty-requestlog.xml and logback-access.xml
    if [ ! -s "${_csv}" ]; then
        echo '"clientHost","user","dateTime","method","requestUrl","statusCode","contentLength","byteSent","elapssedTime","userAgent","thread"' > ${_csv}
    else
        echo "# Appending into ${_csv} ..."
    fi
    # No $2.
    # Some version doesn't have thread information? ($12)
    # TODO: userAgent ($11) can contain double-quotes, so added "{"
    rg --no-filename -N -z \
        '^([0-9.]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^ ]+) ([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"{]+)" *\[?([^\]]*)\]?' \
        -o -r '"$1","$3","$4","$5","$6","$7","$8","$9","$10","$11","$12"' ${_request_file} >> ${_csv}
}

### Private functions ##################################################################################################

function _split() {
    local _rtn_var_name="$1"
    local _string="$2"
    local _delimiter="${3-,}"
    local _original_IFS="$IFS"
    eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
    IFS="$_original_IFS"
}

function _getAfterFirstMatch() {
    local _file_path="$1"
    local _start_regex="$2"
    local _end_regex="$3"
    local _exclude_first_line="$4"
    local _extension="${_file_path##*.}"

    local _start_line_num=`rg -z -n -m1 "$_start_regex" "$_file_path" | cut -d ":" -f 1`
    if [ -n "$_start_line_num" ]; then
        local _end_line_num="\$"
        if [ -n "$_end_regex" ]; then
            #_sed -n "${_start_line_num},\$s/${_end_regex}/&/p" "$_file_path"
            local _tmp_start_line_num=$_start_line_num
            [[ "$_exclude_first_line" =~ ^(y|Y) ]] && _tmp_start_line_num=$(($_start_line_num + 1))
            if [ "${_extension}" = 'gz' ]; then
                _end_line_num=`gunzip -c "$_file_path" | tail -n +${_tmp_start_line_num} | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            else
                _end_line_num=`tail -n +${_tmp_start_line_num} "$_file_path" | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            fi
            _end_line_num=$(( $_end_line_num + $_start_line_num - 1 ))
        fi
        if [ "${_extension}" = 'gz' ]; then
            gunzip -c "${_file_path}" | _sed -n "${_start_line_num},${_end_line_num}p"
        else
            _sed -n "${_start_line_num},${_end_line_num}p" "${_file_path}"
        fi
    fi
}

function _date2int() {
    local _date_str="$1"
    [[ "${_date_str}" =~ ^[0-9][0-9]\/[0-9][0-9]\/[0-9][0-9].[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]] && _date_str="`dateconv "${_date_str}" -i "%y/%m/%d %H:%M:%S" -f "%Y-%m-%d %H:%M:%S"`"
    _date -d "${_date_str}" +"%s"
}

function _find_and_cat() {
    local _name="$1"
    local _once="$2"
    # Accept not only file name but also /<dir>/<filename>
    for _f in `find . -type f -print | grep -w "${_name}$"`; do
        if [ -n "${_f}" ]; then
            echo "## ${_f}" >&2
            cat "${_f}"
            echo ''
            [[ "${_once}" =~ ^(y|Y) ]] && break
        fi
    done
}

function _replace_number() {
    _sed -r "s/[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+/__UUID__/g" \
     | _sed -r "s/0x[0-9a-f][0-9a-f]+/0x_HEX_/g" \
     | _sed -r "s/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/_HEX_/g" \
     | _sed -r "s/20[0-9][0-9][-/][0-9][0-9][-/][0-9][0-9][ T]/_DATE_ /g" \
     | _sed -r "s/[0-2][0-9]:[0-6][0-9]:[0-6][0-9][.,0-9]*/_TIME_/g" \
     | _sed -r "s/-[0-9]+\]\s+\{/-N] {/g" \
     | _sed -r "s/[0-9][0-9][0-9][0-9][0-9]+/_NUM_/g"
}

function _load_yaml() {
    local _yaml_file="${1}"
    local _name_space="${2}"
    [ -s "${_yaml_file}" ] || return 1
    # TODO: probably this can be done only with awk
    #awk -F "=" '{out=$2;gsub(/[^0-9a-zA-Z_]/,"_",$1);for(i=3;i<=NF;i++){out=out"="$i};print $1"=\""$out"\""}' ${_yaml_file} > /tmp/_load_yaml.out || return $?
    _sed -n -r 's/^([^=]+)[[:space:]]+=[[:space:]]+(.+)/'${_name_space}'\1\t"\2"/p' ${_yaml_file} | awk -F "\t" '{gsub(/[^0-9a-zA-Z_]/,"_",$1); print $1"="$2}' > /tmp/_load_yaml.out || return $?
    source /tmp/_load_yaml.out
}

function _search_properties() {
    local _path="${1-./}"
    local _props="$2" # space separated regex
    local _is_name_value_xml="$3"

    for _p in ${_props}; do
        if [[ "${_is_name_value_xml}" =~ (^y|^Y) ]]; then
            local _out="`_grep -Pzo "(?s)<name>${_p}</name>.+?</value>" ${_path}`"
            [[ "${_out}" =~ (<value>)(.*)(</value>) ]]
            echo "${_p}=${BASH_REMATCH[2]}"
        else
            # Expecting hive 'set' command output or similar style (prop=value)
            _grep -P "${_p}" "${_path}"
        fi
    done
}

function _get_json() {
    local _props="$1"           # python list string ['xxxx','yyyy','key[:=]value'] (*NO* space)
    local _key="${2-"key"}"     # a key attribute name. eg: '@class' (OrientDB), 'key' (jmx.json)
    local _attrs="${3-"value"}" # attribute1,attribute2 to return only those attributes' value
    local _find_all="${4}"      # If Y, not stopping after finding one
    local _no_pprint="${5}"     # no prettified output
    # Requires jn_utils.py
    python3 -c 'import sys,json,re
m = ptn_c = None
if len("'${_key}'") > 0:
    ptn_c = re.compile("[\"]?('${_key}')[\"]?\s*[:=]\s*[\"]?([^\"]+)[\"]?")
attrs = []
if len("'${_attrs}'") > 0:
    attrs = "'${_attrs}'".split(",")
_d = json.loads(sys.stdin.read())
for _p in '${_props}':
    if len("'${_key}'") > 0:
        m = ptn_c.search(_p)
    if m and type(_d) == list:
        (_k, _k_name) = m.groups()
        _tmp_d = []
        for _i in _d:
            if _k in _i and _i[_k] == _k_name:
                _tmp_dd = {}
                for _a in attrs:
                    _tmp_dd[_a] = _i[_a]
                _tmp_d.append(_tmp_dd)
                if "'${_find_all}'".lower() != "y":
                    break
        if bool(_tmp_d) is False:
            _d = None
            break
        if len(_tmp_d) == 1:
            _d = _tmp_d[0]
        else:
            _d = _tmp_d
    elif _p in _d:
        _d = _d[_p]
    else:
        _d = None
        break
if "'${_no_pprint}'".lower() == "y":
    print(_d)
else:
    print(json.dumps(_d, indent=4))
'
}

function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}
function _csplit() {
    local _cmd="csplit"; which gcsplit &>/dev/null && _cmd="gcsplit"
    ${_cmd} "$@"
}
function _grep() {
    local _cmd="grep"; which grep &>/dev/null && _cmd="ggrep"
    ${_cmd} "$@"
}
function _date() {
    local _cmd="date"; which gdate &>/dev/null && _cmd="gdate"
    ${_cmd} "$@"
}
function _tac() {
    local _cmd="tac"; which gtac &>/dev/null && _cmd="gtac"
    ${_cmd} "$@"
}



### Help ###############################################################################################################

_help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        # The workd "help" is already taken in bash
        echo "_help <function name> [Y]"
        echo ""
        _list "func"
        echo ""
        return
    fi

    local _output=""
    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | _grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            echo "Function name '$_function_name' does not exist."
            return 1
        fi

        eval "$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        if [ -z "$__doc__" ]; then
            _output="No help information in function name '$_function_name'.\n"
        else
            _output="$__doc__"
            if [[ "${_doc_only}" =~ (^y|^Y) ]]; then
                echo -e "${_output}"; return
            fi
        fi

        local _params="$(type $_function_name 2>/dev/null | _grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | _grep -v awk)"
        if [ -n "$_params" ]; then
            _output="${_output}Parameters:\n"
            _output="${_output}${_params}\n"
        fi
        if [[ "${_show_code}" =~ (^y|^Y) ]] ; then
            _output="${_output}\n${_code}\n"
            echo -e "${_output}" | less
        elif [ -n "$_output" ]; then
            echo -e "${_output}"
            echo "(\"_help $_function_name y\" to show code)"
        fi
    else
        echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}
_list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | _grep -P '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | _sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`_help "$_f" "" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | _grep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | _grep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | _grep ^[r]_
    fi
}

### Global variables ###################################################################################################
# TODO: Not using at this moment
_IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
_IP_RANGE_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])?$'
_HOSTNAME_REGEX='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
_TEST_REGEX='^\[.+\]$'
_SCRIPT_DIR="$(dirname $(realpath "$BASH_SOURCE"))"

[ -z "$_DATE_FORMAT" ] && _DATE_FORMAT="\d\d\d\d-\d\d-\d\d"
[ -z "$_TIME_FMT4CHART" ] && _TIME_FMT4CHART="\d\d:"


### Main ###############################################################################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    usage | less
fi