## Simple/generic alias commands (some need pip though) ################################################################
# 'cd' to last modified directory
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias fd='find . -name'
alias fcv='fc -e vim'
alias pjt='python -m json.tool'
alias urldecode='python -c "import sys, urllib as ul; print(ul.unquote_plus(sys.argv[1]))"'
#alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print(ul.quote(sys.argv[1]))"'
# base64 encode/decode (coreutils base64 or openssl base64 -e|-d)
alias b64encode='python -c "import sys, base64; print(base64.b64encode(sys.argv[1]))"'
alias b64decode='python -c "import sys, base64; print(base64.b64decode(sys.argv[1]))"'
alias utc2int='python3 -c "import sys,time,dateutil.parser;from datetime import timezone;print(int(dateutil.parser.parse(sys.argv[1]).replace(tzinfo=timezone.utc).timestamp()))"'  # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python -c "import sys,datetime;print(datetime.datetime.utcfromtimestamp(int(sys.argv[1][0:10])).strftime(\"%Y-%m-%d %H:%M:%S\")+\".\"+sys.argv[1][10:13]+\" UTC\")"'
#alias int2utc='python -c "import sys,time;print(time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\")"'
alias dec2hex='printf "%x\n"'
alias hex2dec='printf "%d\n"'
#alias python_i_with_pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);pdf=pd.DataFrame(jd);")'   # Start python interactive after loading json object in 'pdf' (pandas dataframe)
alias python_i_with_pandas='python3 -i <(echo "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);print(pdf)")'        # to convert list/dict pdf.values.tolist()
alias python_i_with_json='python3 -i <(echo "import sys,json;jso=json.load(open(sys.argv[1]))")'
alias json2csv='python3 -c "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);pdf.to_csv(sys.argv[1]+\".csv\", header=True, index=False)"'
# Read xml file, then convert to dict, then print json
alias xml2json='python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))"'
alias prettyjson='python3 -c "import sys,json;print(json.dumps(json.load(open(sys.argv[1])), indent=4, sort_keys=True))"'
# Pretty print XML. NOTE: without encoding, etree.tostring returns bytes, which does not work with print()
alias prettyxml='python3 -c "import sys;from lxml import etree;t=etree.parse(sys.argv[1].encode(\"utf-8\"));print(etree.tostring(t,encoding=\"unicode\",pretty_print=True))"'
#alias prettyxml='xmllint --format'
# TODO: find with sys.argv[2] (no ".//"), then output as string
alias xml_get='python3 -c "import sys;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();print(r.find(sys.argv[2],namespaces=r.nsmap))"'
# Search with 2nd arg and output the path(s)
alias xml_path='python -c "import sys,pprint;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();pprint.pprint([t.getelementpath(x) for x in r.findall(\".//\"+sys.argv[2],namespaces=r.nsmap)])"'
# Strip XML / HTML to get text. NOTE: using sys.stdin.read. (TODO: maybe </br> without new line should add new line)
alias strip_tags='python3 -c "import sys,html,re;rx=re.compile(r\"<[^>]+>\");print(html.unescape(rx.sub(\"\",sys.stdin.read())))"'
alias jp='jupyter-lab &> /tmp/jupyter-lab.out &'
alias jn='jupyter-notebook &> /tmp/jupyter-notebook.out &'
# 'time' with format
alias timef='/usr/bin/time -f"[%Us user %Ss sys %es real %MkB mem]"'    # brew install gnu-time --with-default-names
# In case 'tree' is not installed
which tree &>/dev/null || alias tree="pwd;find . | sort | sed '1d;s/^\.//;s/\/\([^/]*\)$/|--\1/;s/\/[^/|]*/|  /g'"
# Debug network performance with curl
alias curld='curl -w "\ntime_namelookup:\t%{time_namelookup}\ntime_connect:\t%{time_connect}\ntime_appconnect:\t%{time_appconnect}\ntime_pretransfer:\t%{time_pretransfer}\ntime_redirect:\t%{time_redirect}\ntime_starttransfer:\t%{time_starttransfer}\n----\ntime_total:\t%{time_total}\nhttp_code:\t%{http_code}\nspeed_download:\t%{speed_download}\nspeed_upload:\t%{speed_upload}\n"'
# output the longest line *number* as wc|gwc -L does not show the line number
alias wcln="awk 'length > max_length { max_length = length; longest_line_num = NR } END { print longest_line_num }'"
# Sum integer in a column by using paste (which concatenates files or characters(+))
alias sum_cols="gpaste -sd+ | bc"
# 10 seconds is too short
alias docker_stop="docker stop -t 120"
alias qcsv='q -O -d"," -T --disable-double-double-quoting'
alias pgbg='pgbadger --timezone 0'

## Non default (need to install an app or develop script) alias commands ###############################################
# Load/source my own searching utility functions / scripts
#mkdir -p $HOME/IdeaProjects/samples/bash; curl -o $HOME/IdeaProjects/samples/bash/log_search.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
alias logS="source $HOME/IdeaProjects/samples/bash/log_search.sh; source $HOME/IdeaProjects/work/bash/log_search.sh"
alias instSona="source $HOME/IdeaProjects/work/bash/install_sonatype.sh"
alias xmldiff="python $HOME/IdeaProjects/samples/python/xml_parser.py"
alias ss="bash $HOME/IdeaProjects/samples/bash/setup_standalone.sh"

# VM related
# virt-manager remembers the connections, so normally would not need to start in this way.
alias kvm_haji='virt-manager -c "qemu+ssh://root@hajime/system?socket=/var/run/libvirt/libvirt-sock" &>/tmp/virt-manager.out &'

# Java / jar related
alias mb='nohup java -jar $HOME/Applications/metabase.jar &'    # port is 3000
alias vnc='nohup java -jar $HOME/Applications/tightvnc-jviewer.jar &>/tmp/vnc-java-viewer.out &'
#alias vnc='nohup java -jar $HOME/Applications/VncViewer-1.9.0.jar &>/tmp/vnc-java-viewer.out &'
alias samurai='nohup java -Xmx4096m -jar $HOME/Apps/samurali/samurai.jar &'
alias gcviewer='nohup java -Xmx4g -jar $HOME/Apps/gcviewer/gcviewer-1.36.jar &'
alias groovyi='groovysh -e ":set interpreterMode true"'

# Chrome aliases for Mac (URL needs to be IP as hostname wouldn't be resolvable on remote)
#alias shib-local='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/local --proxy-server=socks5://localhost:28081'
#alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=socks5://dh1:28081 http://192.168.1.31:4200/webuser/'
alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=http://dh1:28080 http://192.168.1.31:4200/webuser/'
alias hblog='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/hajigle https://www.blogger.com/blogger.g?blogID=9018688091574554712&pli=1#allposts'

# Work specific aliases
alias hwxS3='s3cmd ls s3://private-repo-1.hortonworks.com/HDP/centos7/2.x/updates/'
# TODO: public-repo-1.hortonworks.com private-repo-1.hortonworks.com
# Slack API Search
[ -s $HOME/IdeaProjects/samples/python/SimpleWebServer.py ] && alias slackS="cd $HOME/IdeaProjects/samples/python/ && nohup python ./SimpleWebServer.py &> /tmp/SimpleWebServer.out &"
[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py ] && alias sptZip3="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py"
[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus2-support-zip.py ] && alias sptZip2="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus2-support-zip.py"
[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py ] && alias sptDumpScript="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py"


### Functions (some command syntax does not work with alias eg: sudo) ##################################################
#eg: date_calc "17:15:02.123 -262.708 seconds"
function date_calc() {
    local _d_opt="$1"
    local _d_fmt="${2:-"%Y-%m-%d %H:%M:%S.%3N"}"    #%d/%b/%Y:%H:%M:%S
    local _cmd="date"
    which gdate &>/dev/null && _cmd="gdate"
    ${_cmd} -u  +"${_d_fmt}" -d"${_d_opt}"
}
#eg: time_calc_ms "02:30:00" 39381000 to add milliseconds to the hh:mm:ss
function time_calc_ms() {
    local _time="$1"    #hh:mm:ss.sss
    local _ms="$2"
    local _sec=`bc <<< "scale=3; ${_ms} / 1000"`
    if [[ ! "${_sec}" =~ ^[+-] ]]; then
        _sec="+${_sec}"
    fi
    date_calc "${_time} ${_sec} seconds"
}
# Obfuscate string (encode/decode)
# How-to: echo -n "your secret word" | obfuscate "your salt"
function obfuscate() {
    local _salt="$1"
    # -pbkdf2 does not work with 1.0.2 on CentOS. Should use -aes-256-cbc?
    # 2>/dev/null to hide WARNING : deprecated key derivation used.
    openssl enc -aes-128-cbc -md sha256 -salt -pass pass:"${_salt}" 2>/dev/null
}
# cat /your/secret/file | deobfuscate "your salt"
function deobfuscate() {
    local _salt="$1"
    openssl enc -aes-128-cbc -md sha256 -salt -pass pass:"${_salt}" -d 2>/dev/null
}
# Merge split zip files to one file
function merge_zips() {
    local _first_file="$1"
    zip -FF ${_first_file} --output ${_first_file%.*}.merged.zip
}
# head and tail of one file
function head_tail() {
    local _f="$1"
    local _n="${2:-1}"
    if [[ "${_f}" =~ \.(log|csv) ]]; then
        local _tac="tac"
        which gtac &>/dev/null && _tac="gtac"
        rg '(^\d\d\d\d-\d\d-\d\d|\d\d.[a-zA-Z]{3}.\d\d\d\d).\d\d:\d\d:\d\d' -m ${_n} ${_f}
        ${_tac} ${_f} | rg '(^\d\d\d\d-\d\d-\d\d|\d\d.[a-zA-Z]{3}.\d\d\d\d).\d\d:\d\d:\d\d' -m ${_n}
    else
        head -n ${_n} "${_f}"
        tail -n ${_n} "${_f}"
    fi
}
# make a directory and cd
function mcd() {
    local _path="$1"
    mkdir "${_path}"; cd "${_path}"
}
function jsondiff() {
    local _f1="$(echo $1 | sed -e 's/^.\///' -e 's/[/]/_/g')"
    local _f2="$(echo $2 | sed -e 's/^.\///' -e 's/[/]/_/g')"
    # alternative https://json-delta.readthedocs.io/en/latest/json_diff.1.html
    python3 -c "import sys,json;print(json.dumps(json.load(open('${_f1}')), indent=4, sort_keys=True))" > "/tmp/${_f1}"
    python3 -c "import sys,json;print(json.dumps(json.load(open('${_f2}')), indent=4, sort_keys=True))" > "/tmp/${_f2}"
    #prettyjson $2 > "/tmp/${_f2}"
    vimdiff "/tmp/${_f1}" "/tmp/${_f2}"
}
# Convert yml|yaml file to a sorted json. Can be used to validate yaml file
function yaml2json() {
    local _yaml_file="${1}"
    # pyyaml doesn't like ********
    cat "${_yaml_file}" | sed 's/\*\*+/__PASSWORD__/g' | python3 -c 'import sys, json, yaml
try:
    print(json.dumps(yaml.safe_load(sys.stdin), indent=4, sort_keys=True))
except yaml.YAMLError as e:
    sys.stderr.write(e+"\n")
'
}
# surprisingly it's not easy to trim|remove all newlines with bash
function rmnewline() {
    python -c 'import sys
for l in sys.stdin:
   sys.stdout.write(l.rstrip("\n"))'
}
# Find recently modified (log) files
function _find_recent() {
    local _dir="${1}"
    local _file_glob="${2:-"*.log"}"
    local _follow_symlink="${3}"
    local _base_dir="${4:-"."}"
    local _mmin="${5-"-60"}"
    if [ ! -d "${_dir}" ]; then
        _dir=$(if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
            realpath $(find -L ${_base_dir%/} -type d \( -name log -o -name logs \) | tr '\n' ' ') | sort | uniq | tr '\n' ' '
        else
            find ${_base_dir%/} -type d \( -name log -o -name logs \)| tr '\n' ' '
        fi 2>/dev/null | tail -n1)
    fi
    [ -n "${_mmin}" ] && _mmin="-mmin ${_mmin}"
    if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
        realpath $(find -L ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' ') | sort | uniq | tr '\n' ' '
    else
        find ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' '
    fi
}
# Tail recnetly modified log files
function tail_logs() {
    local _log_dir="${1}"
    local _log_file_glob="${2:-"*.log"}"
    tail -n20 -f $(_find_recent "${_log_dir}" "${_log_file_glob}")
}
# Grep only recently modified files (TODO: should check if ggrep or rg is available)
function grep_logs() {
    local _search_regex="${1}"
    local _log_dir="${2}"
    local _log_file_glob="${3:-"*.log"}"
    local _grep_opts="${4:-"-IrsP"}"
    grep ${_grep_opts} "${_search_regex}" $(_find_recent "${_log_dir}" "${_log_file_glob}")
}
# prettify any strings by checkinbg braces
function prettify() {
    local _str="$1"
    local _pad="${2-"    "}"
    #local _oneline="${3:-Y}"
    #[[ "${_oneline}" =~ ^[yY] ]] && _str="$(echo "${_str}" | tr -d '\n')"
    # TODO: convert to pyparsing (or think about some good regex)
    python -c "import sys
s = '${_str}';n = 0;p = '${_pad}';f = False;
if len(s) == 0:
    for l in sys.stdin:
        s += l
i = 0;
while i < len(s):
    if s[i] in ['(', '[', '{']:
        if (s[i] == '(' and s[i + 1] == ')') or (s[i] == '[' and s[i + 1] == ']') or (s[i] == '{' and s[i + 1] == '}'):
            sys.stdout.write(s[i] + s[i + 1])
            i += 1
        else:
            n += 1
            sys.stdout.write(s[i] + '\n' + (p * n))
            f = True
    elif s[i] in [',']:
        sys.stdout.write(s[i] + '\n' + (p * n))
        f = True
    elif s[i] in [')', ']', '}']:
        n -= 1
        sys.stdout.write('\n' + (p * n) + s[i])
    else:
        sys.stdout.write(s[i])
    if f:
        if (i + 1) < len(s) and s[i + 1] == ' ' and ((i + 2) < len(s) and s[i + 2] != ' '):
            i += 1
    f = False
    i += 1"
}
# Grep against jar file to find a class ($1)
function jargrep() {
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${2:-./} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} | grep -wi '$1' && echo {}"
}
# Execute multiple commands concurrently. NOTE: seems Mac's xargs has command length limit and no -r to ignore empty line
function _parallel() {
    local _cmds_list="$1"   # File or strings of commands
    local _prefix_cmd="$2"  # eg: '(date;'
    local _suffix_cmd="$3"  # eg: ';date) &> test_$$.out'
    local _num_process="${4:-3}"
    if [ -f "${_cmds_list}" ]; then
        cat "${_cmds_list}"
    else
        echo ${_cmds_list}
    fi | sed '/^$/d' | tr '\n' '\0' | xargs -t -0 -n1 -P${_num_process} -I @@ bash -c "${_prefix_cmd}@@${_suffix_cmd}"
    # Somehow " | sed 's/"/\\"/g'" does not need... why?
}
# Escape characters for Shell
function _escape() {
    local _string="$1"
    printf %q "${_string}"
}
# Grep STDIN with \d\d\d\d-\d\d-\d\d.\d\d:\d (upto 10 mins) and pass to bar_chart
function bar() {
    local _datetime_regex="${1}"
    [ -z "${_datetime_regex}" ] && _datetime_regex="^\d\d\d\d-\d\d-\d\d.\d\d:\d"
    #ggrep -oP "${2:-^\d\d\d\d-\d\d-\d\d.\d\d:\d}" ${1-./*} | bar_chart.py
    rg "${_datetime_regex}" -o | sed 's/ /./g' | bar_chart.py
}
# Start Jupyter Lab as service
function jpl() {
    local _dir="${1:-"."}"
    local _kernel_timeout="${2-10800}"
    local _shutdown_timeout="${3-115200}"

    local _conf="$HOME/.jupyter/jpl_tmp_config.py"
    local _log="/tmp/jpl_${USER}_$$.out"
    if [ ! -d "$HOME/.jupyter" ]; then mkdir "$HOME/.jupyter" || return $?; fi
    > "${_conf}"
    [[ "${_kernel_timeout}" =~ ^[0-9]+$ ]] && echo "c.MappingKernelManager.cull_idle_timeout = ${_kernel_timeout}" >> "${_conf}"
    [[ "${_shutdown_timeout}" =~ ^[0-9]+$ ]] && echo "c.NotebookApp.shutdown_no_activity_timeout = ${_shutdown_timeout}" >> "${_conf}"

    echo "Redirecting STDOUT / STDERR into ${_log}" >&2
    nohup jupyter lab --ip=`hostname -I | cut -d ' ' -f1` --no-browser --config="${_conf}" --notebook-dir="${_dir%/}" 2>&1 | tee "${_log}" | grep -m1 -oE "http://`hostname -I | cut -d ' ' -f1`:.+token=.+" &
}
# Mac only: Start Google Chrome in incognito with proxy
function chromep() {
    local _host_port="${1:-"192.168.6.163:28081"}"
    local _url=${2}
    local _port=${3:-28081}

    local _host="${_host_port}"
    if [[ "${_host_port}" =~ ^([a-zA-Z0-9.-]+):([0-9]+)$ ]]; then
        _host="${BASH_REMATCH[1]}"
        _port="${BASH_REMATCH[2]}"
    fi
    [ ! -d $HOME/.chromep/${_host}_${_port} ] && mkdir -p $HOME/.chromep/${_host}_${_port}
    [ -n "${_url}" ] && [[ ! "${_url}" =~ ^http ]] && _url="http://${_url}"
    #nohup "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --user-data-dir=$HOME/.chromep/${_host}_${_port} --proxy-server="socks5://${_host}:${_port}" ${_url} &>/tmp/chrome.out &
    open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/${_host}_${_port} --proxy-server=socks5://${_host}:${_port} ${_url}
    echo 'open -na "Google Chrome" --args --user-data-dir=$(mktemp -d) --proxy-server=socks5://'${_host}':'${_port}' '${_url}
}
# Add route to dockerhost to access containers directly
function r2dh() {
    local _dh="${1}"  # docker host IP or L2TP 10.0.1.1
    local _3rd="${2-100}"  # 3rd decimal in network address
    [ -z "${_dh}" ] && _dh="$(ifconfig ppp0 | grep -oE 'inet .+' | awk '{print $4}')" 2>/dev/null
    [ -z "${_dh}" ] && _dh="dh1"

    if [ "Darwin" = "`uname`" ]; then
        [ -n "${_3rd}" ] && ( sudo route delete -net 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 ${_dh} )
        sudo route delete -net 172.17.0.0/24 &>/dev/null;sudo route add -net 172.17.0.0/24 ${_dh}
        sudo route delete -net 172.18.0.0/24 &>/dev/null;sudo route add -net 172.18.0.0/24 ${_dh}
    elif [ "Linux" = "`uname`" ]; then
        [ -n "${_3rd}" ] && ( sudo ip route del 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 gw ${_dh} ens3 )
    else    # Assuming windows (cygwin)
        [ -n "${_3rd}" ] && ( route delete 172.17.${_3rd}.0 &>/dev/null;route add 172.17.${_3rd}.0 mask 255.255.255.0 ${_dh} )
    fi
}
function sshs() {
    local _user_at_host="$1"
    local _session_name="${2}"
    local _cmd="screen -r || screen -ls"
    if [ -n "${_session_name}" ]; then
        _cmd="screen -x ${_session_name} || screen -S ${_session_name}"
    else
        # if no session name specified, tries to attach it anyway (if only one session, should work)
        _cmd="screen -x || screen -x $USER || screen -S $USER"
    fi
    ssh ${_user_at_host} -t ${_cmd}
}
# backup commands
function backupC() {
    local _src="${1:-"$HOME/Documents/cases"}"
    local _dst="${2:-"hosako@z230:/cygdrive/h/hajime/cases"}"

    [ ! -d "${_src}" ] && return 11
    [ ! -d "$HOME/.Trash" ] && return 12

    local _mv="mv --backup=t"
    [ "Darwin" = "`uname`" ] && _mv="gmv --backup=t"

    ## Special: support_tmp directory wouldn't need to backup
    find ${_src%/} -type d -mtime +30 -name '*_tmp' -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/

    # Delete files larger than _size (10MB) and older than one year
    find ${_src%/} -type f -mtime +365 -size +10000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    # Delete files larger than 60MB and older than 180 days
    find ${_src%/} -type f -mtime +180 -size +60000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    # Delete files larger than 100MB and older than 90 days
    find ${_src%/} -type f -mtime +90 -size +100000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    # Delete files larger than 500MB and older than 60 days
    find ${_src%/} -type f -mtime +60 -size +500000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    wait
    # Sync all files smaller than _size (10MB), means *NO* backup for files over 10MB.
    rsync -Pvaz --bwlimit=10240 --max-size=10000k --modify-window=1 ${_src%/}/ ${_dst%/}/
}
# synchronising my search.osakos.com
function push2search() {
    local _force="$1"
    # May need to configure .ssh/config to specify the private key
    local _cmd="rsync -vrc --exclude '.git' --exclude '.idea' --exclude '*.md' $HOME/IdeaProjects/search/ search.osakos.com:~/www/search/"
    if [[ "${_force}" =~ ^[yY] ]]; then
        eval "${_cmd}"
        return $?
    fi
    eval "${_cmd} -n"
    echo ""
    read -p "Are you sure?: " "_yes"
    echo ""
    [[ "${_yes}" =~ ^[yY] ]] && eval "${_cmd}"
}


## Work specific functions
function pubS() {
    scp -C $HOME/IdeaProjects/work/bash/install_sonatype.sh dh1:/var/tmp/share/sonatype/
    cp -f $HOME/IdeaProjects/work/bash/install_sonatype.sh $HOME/share/sonatype/
    scp -C $HOME/IdeaProjects/samples/bash/utils.sh dh1:/var/tmp/share/sonatype/
    cp -f $HOME/IdeaProjects/samples/bash/utils.sh $HOME/share/sonatype/
    scp -C $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh dh1:/var/tmp/share/sonatype/
    cp -f $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh $HOME/share/sonatype/
    date
    sync_nexus_binaries &>/dev/null &
}
function sync_nexus_binaries() {
    local _host="${1:-"dh1"}"
    echo "Synchronising IQ binaries from/to ${_host} ..." >&2
    rsync -Prc root@${_host}:/var/tmp/share/sonatype/nexus-iq-server-*-bundle.tar.gz $HOME/.nexus_executable_cache/
    rsync -Prc $HOME/.nexus_executable_cache/nexus-iq-server-*-bundle.tar.gz root@${_host}:/var/tmp/share/sonatype/
}
function sptBoot() {
    local _zip="$1"
    local _jdb="$2"

    [ -s $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py ] || return 1
    if [ -z "${_zip}" ]; then
        _zip="$(ls -1 ./*-202?????-??????*.zip | tail -n1)" || return $?
        echo "Using ${_zip} ..."
    fi
    #echo "To just re-launch or start, check relaunch-support.sh"
    if [ ! -s $HOME/.nexus_executable_cache/ssl/keystore.jks.orig ]; then
        echo "Replacing keystore.jks ..."
        mv $HOME/.nexus_executable_cache/ssl/keystore.jks $HOME/.nexus_executable_cache/ssl/keystore.jks.orig
        cp $HOME/IdeaProjects/samples/misc/standalone.localdomain.jks $HOME/.nexus_executable_cache/ssl/keystore.jks
        echo "Append 'local.standalone.localdomain' in 127.0.0.1 line in /etc/hosts."
    fi
    if [[ "${_jdb}" =~ ^(y|Y) ]]; then
        python3 $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py --remote-debug -cr "${_zip}" ./$(basename "${_zip}" .zip)_tmp
    else
        python3 $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py -cr "${_zip}" ./$(basename "${_zip}" .zip)_tmp
    fi || echo "NOTE: If error was port already in use, you might need to run below:
    . ~/IdeaProjects/work/bash/install_sonatype.sh
    f_sql_nxrm \"config\" \"SELECT attributes['docker']['httpPort'] FROM repository WHERE attributes['docker']['httpPort'] IS NOT NULL\" \".\" \"\$USER\"
If ports conflict, edit nexus.properties is easier. eg:8080.
"
}
# To start local (on Mac) IQ server
function iqStart() {
    local _base_dir="${1:-"."}"
    local _java_opts=${2}
    #local _java_opts=${@:2}
    local _jar_file="$(find ${_base_dir%/} -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    local _cfg_file="$(dirname "${_jar_file}")/config.yml"
    grep -qE '^\s*threshold:\s*INFO$' "${_cfg_file}" && sed -i.bak 's/threshold: INFO/threshold: ALL/g' "${_cfg_file}"
    grep -qE '^\s*level:\s*DEBUG$' "${_cfg_file}" || sed -i.bak -E 's/level: .+/level: DEBUG/g' "${_cfg_file}"
    java -Xmx2g ${_java_opts} -jar "${_jar_file}" server "${_cfg_file}"
}

function iqCli() {
    local __doc__="https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    if [ -z "$1" ]; then
        iqCli "./"
        return $?
    fi
    java -jar /Users/hosako/Apps/iq-clis/nexus-iq-cli.jar -i "${_IQ_APP:-"sandbox-application"}" -s "${_IQ_URL:-"http://dh1.standalone.localdomain:8070/"}" -a "admin:admin123" -r ./iq_result_$(date +'%Y%m%d%H%M%S').json -X $@
}
function iqMvn() {
    # https://help.sonatype.com/display/NXI/Sonatype+CLM+for+Maven
    mvn com.sonatype.clm:clm-maven-plugin:evaluate -Dclm.additionalScopes=test,provided,system -Dclm.applicationId=sandbox-application -Dclm.serverUrl=http://dh1.standalone.localdomain:8070/ -Dclm.username=admin -Dclm.password=admin123
}
function mvn-get() {
    # maven/mvn get/download
    local _gav="$1" # eg: junit:junit:4.12
    local _localrepo="${2-"./local_repo"}"
    #local _repo="$3"
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -Dtransitive=false -U -X"}"
    local _settings_xml="$(find . -maxdepth 2 -name '*settings*.xml' -print | tail -n1)"
    if [ -n "${_settings_xml}" ]; then
        echo "Using ${_settings_xml}..." >&2; sleep 3
        _options="${_options% } -s ${_settings_xml}"
    fi
    [ -n "${_localrepo}" ] && _options="${_options% } -Dmaven.repo.local=${_localrepo}"
    #[ -n "${_repo}" ] && _options="${_options% } -DremoteRepositories=${_repo}"    # Doesn't work
    mvn dependency:get -Dartifact=${_gav} ${_options}
}
function mvn-resolve() {
    # maven/mvn resolve dependency only
    local _repo="$1"
    local _localrepo="$2"
    local _options=""
    [ -n "${_repo}" ] && _options="${_options% } -DremoteRepositories=${_repo}"
    [ -n "${_localrepo}" ] && _options="${_options% } -Dmaven.repo.local=${_localrepo}"
    mvn -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS dependency:resolve ${_options} -U -X
}
# To patch nexus (so that checking /system) but probably no longer using.
function _patch() {
    local _java_file="${1}"
    local _jar_file="${2}"
    local _base_dir="${3:-"."}"
    if [ -z "${_java_file}" ] || [ ! -f "${_java_file}" ]; then
        return 1
    fi
    if [ ! -s $HOME/IdeaProjects/samples/bash/patch_java.sh ]; then
        return 1
    fi
    if [ -z "${_jar_file}" ]; then
        _jar_file="$(find ${_base_dir%/} -type d -name system -print | head -n1)"
    fi
    if [ -z "${CLASSPATH}" ]; then
        echo "old CLASSPATH=${CLASSPATH}"
    fi
    export CLASSPATH=`find ${_base_dir%/} -path '*/system/*' -type f -name '*.jar' | tr '\n' ':'`.
    bash $HOME/IdeaProjects/samples/bash/patch_java.sh "" ${_java_file} ${_jar_file}0
}
function _patch_remote() {
    # TODO: not working?
    local _java_file="${1}"
    local _jar_file="${2}"  # To step faster
    local _port="${3:-8081}"
    local _base_dir="${4:-"/opt/sonatype/nexus"}"
    local _host="${5:-"root@dh1"}"
    local _path="${6:-"/var/tmp/share/sonatype/workspace"}"
    scp -C ${_java_file} ${_host%:}:${_path%/}/ || return $?
    ssh ${_host} "export CLASSPATH=\$(find -L ${_base_dir%/} -path '*/system/*' -type f -name '*.jar' | tr '\n' ':')/var/tmp/share/java/lib/*:.;bash -x /var/tmp/share/java/patch_java.sh ${_port} \"${_path%/}/$(basename ${_java_file})\" \"${_jar_file}\""
}
