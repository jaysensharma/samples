#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Python Jupyter Notebook helper/utility functions
# @author: hajime
#
# curl https://raw.githubusercontent.com/hajimeo/samples/master/python/jn_utils.py -o $HOME/IdeaProjects/samples/python/jn_utils.py
#
"""
jn_utils is Jupyter Notebook Utility script, which contains functions to convert text files to Pandas DataFrame or DB (SQLite) tables.
To update this script, execute "ju.update()".

== Pandas tips (which I often forget) ==================================
To show more strings in the truncated rows:
    pd.options.display.max_rows = 1000      (default is 60)
To show more strings in a column:
    pd.options.display.max_colwidth = 1000  (default is 50. -1 to disable = show everything)
To show the first 3 rows and the last 3 rows:
    df.iloc[[0,1,2,-3,-2,-1]]
Convert one row to dict:
    row = df[:1].to_dict(orient='records')[0]

== Sqlite tips (which I often forget) ==================================
Convert Unix timestamp with milliseconds to datetime
    DATETIME(ROUND(dateColumn / 1000), 'unixepoch')
Convert current time or string date to Unix timestamp
    STRFTIME('%s', 'NOW')
    STRFTIME('%s', UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d+)', max(date_time), 1))
    $ q "select (julianday('2020-05-01 00:10:00') - 2440587.5)*86400.0"
    1588291800.0000045
    $ q "select CAST((julianday('2020-05-01 00:10:00') - julianday('2020-05-01 00:00:00')) * 8640000 AS INT)" <<< milliseconds
    600.0000044703484
"""

# TODO: When you add a new pip package, don't forget to update setup_work.env.sh
import sys, os, fnmatch, gzip, re, linecache, json, sqlite3
from time import time, mktime, strftime
from datetime import datetime
from dateutil import parser
import pandas as pd
from sqlalchemy import create_engine
import matplotlib.pyplot as plt

try:
    from lxml import etree
    import pyjq
    import multiprocessing as mp
    import jaydebeapi
    import IPython
except ImportError:
    # Above modules are not mandatory
    pass

try:
    from urllib.request import urlopen, Request
except ImportError:
    from urllib2 import urlopen, Request

_DEBUG = False
_LOAD_UDFS = True

_LAST_CONN = None
_DB_SCHEMA = 'db'
_SIZE_REGEX = r"[sS]ize ?= ?([0-9]+)"
_TIME_REGEX = r"\b([0-9.,]+) ([km]?s)\b"


def _mexec(func_obj, args_list, num=None):
    """
    Execute multiple functions asynchronously
    :param func_obj: A function object to be executed
    :param args_list: A list contains tuples of arguments
    :param num: number of pool. if None, half of CPUs (NOTE: if threads, it does not matter)
    :return: list contains results. Currently result order is random (not same as args_list)
    >>> def multi(x, y): return x * y
    ...
    >>> _mexec(multi, [(1, 2)])[0]
    2
    >>> rs = _mexec(multi, [(1,2), (2,3)])
    >>> rs[0] + rs[1]
    8
    """
    rs = []
    if bool(args_list) is False or bool(func_obj) is False:
        return None
    # If only one args list, no point of doing multiprocessing
    if len(args_list) == 1:
        rs.append(func_obj(*args_list[0]))
        return rs
    if bool(num) is False:
        num = int(mp.cpu_count() / 2)
    executor = mp.Pool(processes=num)
    rs = executor.starmap_async(func_obj, args_list)
    return rs.get()


def _dict2global(d, scope=None, overwrite=False):
    """
    Iterate the given dict and create global variables (key = value)
    NOTE: somehow this function can't be called from inside of a function in Jupyter
    :param d: a dict object
    :param scope: should pass 'globals()' or 'locals()'
    :param overwrite: If True, instead of throwing error, just overwrites with the new value
    :return: void
    >>> _dict2global({'a':'test', 'b':'test2'}, globals(), True)
    >>> b == 'test2'
    True
    """
    if bool(scope) is False:
        scope = globals()
    for k, v in d.items():
        if k in scope and overwrite is False:
            raise ValueError('%s is already used' % (k))
            # continue
        scope[k] = v


def _chunks(l, n):
    """
    Split/Slice a list by the size 'n'
    From https://stackoverflow.com/questions/312443/how-do-you-split-a-list-into-evenly-sized-chunks
    :param l: A list object
    :param n: Chunk size
    :return: New list
    >>> _chunks([1,2,3,4,5], 2)
    [[1, 2], [3, 4], [5]]
    """
    return [l[i:i + n] for i in range(0, len(l), n)]  # xrange is replaced


def _globr(ptn='*', src='./', loop=0):
    """
    As Python 2.7's glob does not have recursive option
    :param ptn: glob regex pattern
    :param src: source/importing directory path
    :return: list contains matched file paths
    >>> l = _globr();len(l) > 0
    True
    """
    matches = []
    n = 0
    for root, dirnames, filenames in os.walk(src):
        # os walk doesn't sort and almost random
        for filename in fnmatch.filter(sorted(filenames), ptn):
            matches.append(os.path.join(root, filename))
            n = n + 1
            if loop > 0 and n >= loop:
                break
        if loop > 0 and n >= loop:
            break
    return matches


def _is_numeric(some_num):
    """
    Python's isnumeric return False for float!!!
    :param some_num:
    :return: boolean
    """
    try:
        float(some_num)
        return True
    except:
        return False


def _open_file(file):
    """
    Open one text or gz file
    :param file:
    :return: file handler
    >>> f = _open_file(__file__);f.name == __file__
    True
    """
    if not os.path.isfile(file):
        return None
    if file.endswith(".gz"):
        _debug("opening %s" % (file))
        return gzip.open(file, "rt")
    else:
        return open(file, "r")


def _read(file):
    """
    Read one text or gz file
    :param file:
    :return: strings of contents
    >>> s = _read(__file__);bool(s)
    True
    """
    f = _open_file(file)
    return f.read()


def _generator(obj):
    """
    Return generator so that don't need to worry about List or Dict for looping
    :param obj: dict or list
    :return: Generator object
    """
    return obj if isinstance(obj, dict) else (i for i, v in enumerate(obj))


def _timestamp(unixtimestamp=None, format=None):
    """
    Format Unix Timestamp with a given format
    :param unixtimestamp: Int (or float, but number after dot will be ignored)
    :param format: Default is %Y-%m-%d %H:%M:%S.%f[:-3]
    :return: Formatted string
    >>> dt_str = _timestamp(1543189639)
    >>> dt_str.startswith('2018')
    True
    """
    if bool(unixtimestamp) is False:
        unixtimestamp = time()
    # TODO: wanted to use timezone.utc but python 2.7 doesn't work
    dt = datetime.fromtimestamp(float(unixtimestamp))
    if format is None:
        return dt.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
    return dt.strftime(format)


def _err(message):
    sys.stderr.write("%s\n" % (str(message)))


def _debug(message):
    global _DEBUG
    if _DEBUG:
        sys.stderr.write("[%s] DEBUG: %s\n" % (_timestamp(), str(message)))


def load_jsons(src="./", conn=None, include_ptn='*.json', exclude_ptn='', chunksize=1000,
               json_cols=['connectionId', 'planJson', 'json']):
    """
    Find json files from current path and load as pandas dataframes object
    :param src: source/importing directory path
    :param conn: If connection object is given, convert JSON to table
    :param include_ptn: Regex string to include some file
    :param exclude_ptn: Regex string to exclude some file
    :param chunksize: Rows will be written in batches of this size at a time. By default, all rows will be written at once
    :param json_cols: to_sql() fails if column is json, so dropping for now (TODO)
    :return: A tuple contain key=>file relationship and Pandas dataframes objects
    #>>> (names_dict, dfs) = load_jsons(src="./engine/aggregates")
    #>>> bool(names_dict)
    #True
    >>> pass    # TODO: implement test
    """
    names_dict = {}
    dfs = {}
    ex = re.compile(exclude_ptn)

    files = _globr(include_ptn, src)
    for f in files:
        f_name, f_ext = os.path.splitext(os.path.basename(f))
        if ex.search(f_name):
            _err("Excluding %s as per exclude_ptn (%d KB)..." % (f_name, os.stat(f).st_size / 1024))
            continue
        new_name = _pick_new_key(f_name, names_dict, using_1st_char=(bool(conn) is False), prefix='t_')
        _err("Creating table: %s (%d KB) ..." % (new_name, os.stat(f).st_size / 1024))
        names_dict[new_name] = f
        dfs[new_name] = json2df(file_path=f, conn=conn, tablename=new_name, chunksize=chunksize,
                                json_cols=json_cols)
    return (names_dict, dfs)


def json2df(filename, jq_query="", conn=None, tablename=None, json_cols=[], chunksize=1000):
    """
    Convert a json file, which contains list into a DataFrame
    If conn is given, import into a DB table
    :param filename: File path or file name or glob pattern
    :param jq_query: String used with ju.jq(), to filter json record
    :param conn:   DB connection object
    :param tablename: If empty, table name will be the filename without extension
    :param json_cols: to_sql() fails if column is json, so forcing those columns to string
    :param chunksize:
    :return: a DataFrame object
    #>>> json2df('./export.json', '.records | map(select(.["@class"] == "quartz_job_detail" and .value_data.jobDataMap != null))[] | .value_data.jobDataMap', ju.connect(), 't_quartz_job_detail')
    #>>> json2df('audit.json', '..|select(.attributes? and .attributes.".typeId" == "db.backup")|.attributes', ju.connect(), "t_audit_attr_dbbackup_logs")
    #>>> ju.json2df(file_path="./audit.json", json_cols=['data'], conn=ju.connect())
    >>> pass    # TODO: implement test
    """
    global _DB_SCHEMA
    if os.path.exists(filename):
        files = [filename]
    else:
        files = _globr(filename)
        if bool(files) is False:
            _err("No file found from: %s ..." % (str(filename)))
            return False
    dfs = []
    for file_path in files:
        _err("Loading %s (%s)..." % (str(file_path), _timestamp(format="%H:%M:%S")))
        if bool(jq_query):
            obj = jq(file_path, jq_query)
            dfs.append(pd.DataFrame(obj))
        else:
            dfs.append(pd.read_json(file_path))  # , dtype=False (didn't help)
    if bool(dfs) is False:
        return False
    df = pd.concat(dfs, sort=False)
    if bool(conn):
        if bool(json_cols) is False:
            row = df[:1].to_dict(orient='records')[0]
            for k in row:
                if type(row[k]) is dict:
                    json_cols.append(k)
        if bool(tablename) is False:
            tablename = _pick_new_key(os.path.basename(files[0]), {}, using_1st_char=False, prefix='t_')
        _err("Creating table: %s ..." % (tablename))
        # TODO: Temp workaround "<table>: Error binding parameter <N> - probably unsupported type."
        df_tmp_mod = _avoid_unsupported(df=df, json_cols=json_cols, name=tablename)
        df_tmp_mod.to_sql(name=tablename, con=conn, chunksize=chunksize, if_exists='replace', schema=_DB_SCHEMA)
        _autocomp_inject(tablename=tablename)
        return len(df) > 0
    return df


def _json2table(filename, tablename=None, conn=None, col_name='json_text', appending=False):
    """
    NOT WORKING
    """
    pass
    if bool(conn) is False:
        conn = connect()
    with open(filename) as f:
        j_obj = json.load(f)
    if not j_obj:
        return False
    j_str = json.dumps(j_obj)

    if bool(tablename) is False:
        tablename = _pick_new_key(filename, {}, using_1st_char=False, prefix='t_')

    if appending is False:
        res = conn.execute("DROP TABLE IF EXISTS %s" % (tablename))
        if bool(res) is False:
            return res
        _err("Drop if exists and Creating table: %s ..." % (str(tablename)))
    else:
        _err("Creating table: %s ..." % (str(tablename)))
    res = conn.execute("CREATE TABLE IF NOT EXISTS %s (%s TEXT)" % (tablename, col_name))  # JSON type not supported?
    if bool(res) is False:
        return res
    return conn.executemany("INSERT INTO " + tablename + " VALUES (?)", str(j_str))


def jq(file_path, query='.', as_string=False):
    """
    Read a json file and query with 'jq' syntax
    NOTE: at this moment, not caching json file contents
    @see https://stedolan.github.io/jq/tutorial/ for query syntax
    :param file_path: Json File path
    :param query: 'jq' query string (looks like dict)
    :param as_string: if true, convert result to string
    :return: whatever pyjq returns
    #>>> pd.DataFrame(ju.jq('./export.json', '.records | map(select(.value_data != null))[] | .value_data'))
    >>> pass    # TODO: implement test
    """
    jd = json2dict(file_path)
    result = pyjq.all(query, jd)
    if len(result) == 1:
        result = result[0]
    if as_string:
        result = str(result)
    return result


def json2dict(file_path, sort=True):
    """
    Read a json file and return as dict
    :param file_path: Json File path
    :param sort:
    :return: Python dict
    >>> pass    # TODO: implement test
    """
    with open(file_path) as f:
        rtn = json.load(f)
    if not rtn:
        return {}
    if sort:
        rtn = json.loads(json.dumps(rtn, sort_keys=sort))
    return rtn


def xml2df(file_path, row_element_name, tbl_element_name=None, conn=None, tablename=None, chunksize=1000):
    """
    Convert a XML file into a DataFrame
    If conn is given, import into a DB table
    :param file_path: File path
    :param row_element_name: Name of XML element which is used to find table rows
    :param tbl_element_name: Name of XML element which is used to find tables (Optional)
    :param conn:   DB connection object
    :param tablename: If empty, table name will be the filename without extension
    :param chunksize:
    :return: a DataFrame object
    #>>> xml2df('./nexus.xml', 'repository', conn=ju.connect())
    >>> pass    # TODO: implement test
    """
    global _DB_SCHEMA
    data = xml2dict(file_path, row_element_name, tbl_element_name)
    df = pd.DataFrame(data)
    if bool(conn):
        if bool(tablename) is False:
            tablename, ext = os.path.splitext(os.path.basename(file_path))
        _err("Creating table: %s ..." % (tablename))
        df.to_sql(name=tablename, con=conn, chunksize=chunksize, if_exists='replace', schema=_DB_SCHEMA)
        _autocomp_inject(tablename=tablename)
    return df


def xml2dict(file_path, row_element_name, tbl_element_name=None, tbl_num=0):
    rtn = []
    parser = etree.XMLParser(recover=True)
    try:
        r = etree.ElementTree(file=file_path, parser=parser).getroot()
        if bool(tbl_element_name) is True:
            tbls = r.findall('.//' + tbl_element_name)
            if len(tbls) > 1:
                _err("%s returned more than 1. Using tbl_num=%s" % (tbl_element_name, str(tbl_num)))
            rows = tbls[tbl_num].findall(".//" + row_element_name)
        else:
            rows = r.findall(".//" + row_element_name)
        _debug("rows num: %d" % (len(rows)))
        for row in rows:
            _row = {}
            for col in list(row):
                _row[col.tag] = ''.join(col.itertext()).strip()
            rtn.append(_row)
    except Exception as e:
        _err(str(e))
    return rtn


def _pick_new_key(name, names_dict, using_1st_char=False, check_global=False, prefix=None):
    """
    Find a non-conflicting a dict key for given name (normally a file name/path)
    :param name: name to be saved or used as a dict key
    :param names_dict: list of names which already exist
    :param using_1st_char: if new name
    :param check_global: Check if new name is used as a global variable
    :param prefix: Appending some string (eg: 'tbl_') at the beginning of the name
    :return: a string of a new dict key which hasn't been used
    >>> _pick_new_key('test', {'test':'aaa'}, False)
    'test1'
    >>> _pick_new_key('test', {'test':'aaa', 't':'bbb'}, True)
    't1'
    """
    name = re.sub(r'\W+', '_', name)
    if using_1st_char:
        name = name[0]
    if bool(prefix):
        new_key = prefix + name
    else:
        new_key = name

    for i in range(0, 9):
        if i > 0:
            new_key = name + str(i)
        if new_key in names_dict and names_dict[new_key] == name:
            break
        if new_key not in names_dict and check_global is False:
            break
        if new_key not in names_dict and check_global is True and new_key not in globals():
            break
    return new_key


def _avoid_unsupported(df, json_cols=[], name=None):
    """
    Drop DF cols to workaround "<table>: Error binding parameter <N> - probably unsupported type."
    :param df: A *reference* of panda DataFrame
    :param json_cols: List contains column names. Ex. ['connectionId', 'planJson', 'json']
    :param name: just for logging
    :return: Modified df
    >>> _avoid_unsupported(pd.DataFrame([{"a_json":"aaa", "test":"bbbb"}]), ["test"])
    Empty DataFrame
    Columns: []
    Index: [0]
    """
    if bool(json_cols) is False:
        return df
    keys = df.columns.tolist()
    cols = {}
    for k in keys:
        _debug("_avoid_unsupported: k = %s" % (str(k)))
        if k in json_cols or k.lower().find('json') > 0:
            # df[k] = df[k].to_string()
            cols[k] = 'str'
    if len(cols) > 0:
        if bool(name): _err(" - converting columns:%s." % (str(cols)))
        return df.astype(cols)
    return df


### Database/DataFrame processing functions
# NOTE: without sqlalchemy is faster
def _db(dbname=':memory:', dbtype='sqlite', isolation_level=None, force_sqlalchemy=False, echo=False):
    """
    Create a DB object. For performance purpose, currently not using sqlalchemy if dbtype is sqlite
    :param dbname: Database name
    :param dbtype: DB type
    :param isolation_level: Isolation level
    :param echo: True output more if sqlalchemy is used
    :return: DB object
    >>> pass    # testing in connect()
    """
    if force_sqlalchemy is False and dbtype == 'sqlite':
        return sqlite3.connect(dbname, isolation_level=isolation_level)
    return create_engine(dbtype + ':///' + dbname, isolation_level=isolation_level, echo=echo)


# Seems sqlite doesn't have regex (need to import pcre.so)
def _udf_regex(regex, item, rtn_idx=0):
    """
    Regex UDF for SQLite
    eg: SELECT UDF_REGEX('queryId=([0-9a-f-]+)', ids, 1) as query_id, ...
    :param regex:   String - Regular expression
    :param item:    String - Column name
    :param rtn_idx: Integer - Grouping result index start from 1
    :return:        Mixed   - Group(idx) result
    """
    matches = re.search(regex, item)
    # If 0, return true or false (expecting to use in WHERE clause)
    if rtn_idx == 0:
        return bool(matches)
    if bool(matches) is False:
        return None
    return matches.group(rtn_idx)


def _udf_str2sqldt(date_time, format):
    """
    Date/Time handling UDF for SQLite
    eg: SELECT UDF_STR2SQLDT('14/Oct/2019:00:00:05 +0800', '%d/%b/%Y:%H:%M:%S %z') as SQLite_DateTime, ...
    :param date_time:   String - Date and Time string
    :param format:      String - Format
    :return:            String - SQLite accepting date time string
    """
    # 14/Oct/2019:00:00:05 +0800 => 2013-10-07 04:23:19.120-04:00
    # https://docs.python.org/3/library/datetime.html#strftime-and-strptime-behavior
    d = datetime.strptime(date_time, format)
    return d.strftime("%Y-%m-%d %H:%M:%S.%f%z")


def _udf_timestamp(date_time):
    """
    @Deprecated: use STRFTIME('%s', 'NOW')
    Unix timestamp handling UDF for SQLite
    eg: SELECT UDF_TIMESTAMP(some_datetime) as unix_timestamp, ...
    NOTE: SQLite way: CAST((julianday(some_datetime) - 2440587.5)*86400.0 as INT)
    :param date_time: ISO date string (or Date/Time column but SQLite doesn't have date/time columns)
    :return:          Integer of Unix Timestamp
    """
    return int(mktime(parser.parse(date_time).timetuple()))


def _udf_str_to_int(some_str):
    """
    Convert \d\d\d\d(MB|M|GB\G) to bytes etc.
    eg: SELECT UDF_STR_TO_INT(some_string) as xxxx, ...
    :param some_str: 350M, 350MB, 350GB, 350G, 60s, 60m, 60ms, 60%
    :return:         Integer
    """
    matches = re.search('([\d.\-]+) ?([a-zA-z%]*)', some_str)
    if bool(matches) is False:
        return None
    num = float(matches.group(1))
    if len(matches.groups()) > 1:
        unit = matches.group(2).upper()
    else:
        return num
    if unit in ['B', 'MS', '%']:
        return num
    if unit in ['G', 'GB']:
        return int(num * 1024 * 1024 * 1024)
    if unit in ['M', 'MB']:
        return int(num * 1024 * 1024)
    if unit in ['K', 'KB']:
        return int(num * 1024)
    if unit in ['S', 'SEC']:
        return int(num * 1000)
    if unit in ['M', 'MIN']:
        return int(num * 1000 * 60)
    if unit in ['H', 'HOUR']:
        return int(num * 1000 * 60 * 60)
    return num


def _udf_num_human_readable(some_numeric, base_unit):
    """
    Convert integer|float|decimal to human readable string.
    eg: SELECT UDF_NUM_HUMAN_READABLE(some_numeric, 'byte') as xxxx, ...
    :param some_numeric: 100, 123.45
    :param base_unit: 'byte' or 'bytes' or 'sec' or 'seconds'
    :return: string
    """
    if _is_numeric(some_numeric):
        return _human_readable_num(some_numeric, base_unit)
    else:
        return some_numeric


def _human_readable_num(some_numeric, base_unit="byte", r=2):
    """
    Convert integer|float|decimal to human readable string.
    eg: SELECT UDF_NUM_HUMAN_READABLE(some_numeric, 'byte') as xxxx, ...
    :param some_numeric: 100, 123.45
    :param base_unit: 'byte' or 'bytes' or 'msec' or 'milliseconds'
    :param r: used in round function
    :return: string|object
    >>> _human_readable_num("1234567890123.756")
    '1.23 TB'
    >>> [dict, list]("1234567890.756", "msec")
    '14.29 h'
    """
    # If some_numeric is not string or not number, loop object and return the object
    if type(some_numeric) in [dict, list]:
        for k in _generator(some_numeric):
            some_numeric[k] = _human_readable_num(some_numeric[k], base_unit)
        return some_numeric
    elif _is_numeric(some_numeric):
        n = float(some_numeric)
        if base_unit in ['byte', 'bytes']:
            units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
            u_idx = int((len(str(int(abs(n)))) - 1) / 3)
            if u_idx == 0:
                return str(round(n, r)) + " " + units[u_idx]
            return str(round(n / (1000 ** u_idx), r)) + " " + units[u_idx]
        elif base_unit in ['msec', 'milliseconds']:
            # base = list(reversed([1000, 60000, 3600000, 86400000]))
            base = [86400000, 3600000, 60000, 1000]
            units = ['d', 'h', 'm', 's', 'ms']
            # Need to be reverse order for time
            for i in _generator(base):
                if abs(n) > base[i]:
                    return str(round(n / base[i], r)) + " " + units[1]
    # Not numeric and not iterable, so no idea
    return some_numeric


def _register_udfs(conn):
    global _LOAD_UDFS
    if _LOAD_UDFS:
        # UDF_REGEX(regex, column, integer)
        conn.create_function("UDF_REGEX", 3, _udf_regex)
        conn.create_function("UDF_STR2SQLDT", 2, _udf_str2sqldt)
        # conn.create_function("UDF_TIMESTAMP", 1, _udf_timestamp)
        conn.create_function("UDF_STR_TO_INT", 1, _udf_str_to_int)
    return conn


def connect(dbname=':memory:', dbtype='sqlite', isolation_level=None, force_sqlalchemy=False, echo=False):
    """
    Connect to a database (SQLite)
    :param dbname: Database name
    :param dbtype: DB type
    :param isolation_level: Isolation level
    :param echo: True output more if sqlalchemy is used
    :return: connection (cursor) object
    >>> import sqlite3;s = connect()
    >>> isinstance(s, sqlite3.Connection)
    True
    """
    global _LAST_CONN
    if bool(_LAST_CONN): return _LAST_CONN

    db = _db(dbname=dbname, dbtype=dbtype, isolation_level=isolation_level, force_sqlalchemy=force_sqlalchemy,
             echo=echo)
    if dbtype == 'sqlite':
        if force_sqlalchemy is False:
            db.text_factory = str
        else:
            db.connect().connection.connection.text_factory = str
        # For 'sqlite, 'db' is the connection object because of _db()
        conn = _register_udfs(db)
    else:
        conn = db.connect()
    if bool(conn): _LAST_CONN = conn
    return conn


def query(sql, conn=None, no_history=False):
    """
    Call pd.read_sql() with given query, expecting SELECT statement
    :param sql: SELECT statement
    :param conn: DB connection object
    :param no_history: not saving this query into a history file
    :return: a DF object
    >>> query("select name from sqlite_master where type = 'table'", connect(), True)
    Empty DataFrame
    Columns: [name]
    Index: []
    """
    if bool(conn) is False: conn = connect()
    # return conn.execute(sql).fetchall()
    # TODO: pd.options.display.max_colwidth = col_width does not work
    df = pd.read_sql(sql, conn)
    # TODO: Trying to set td tags alignment to left but not working
    # dfStyler = df.style.set_properties(**{'text-align': 'left'})
    # dfStyler.set_table_styles([dict(selector='td', props=[('text-align', 'left')])])
    if no_history is False and df.empty is False:
        _save_query(sql)
    return df


q = query


def query_execute(sql, conn):
    """
    Call conn.execute() then conn.fetchall() with given query, expecting SELECT statement
    Comparing to query(), this should support more databases, such as Hive, but NOT SQLite...
    :param sql: (SELECT) SQL statement
    :param conn: DB connection (cursor)
    :return: Panda DataFrame
    #>>> hc = hive_conn("jdbc:hive2://localhost:10000/default")
    #>>> df = query_execute("SELECT 1", hc)
    #>>> bool(df)
    #True
    >>> pass    # TODO: implement test
    """
    conn.execute(sql)
    result = conn.fetchall()
    if bool(result):
        return pd.DataFrame(result)
    return result


def _escape_query(sql):
    """
    TODO: would need to add more characters for escaping (eg: - in table name requires double quotes)
    :param sql:
    :return: string - escaped query
    """
    return sql.replace("'", "''")


def _save_query(sql, limit=1000):
    """
    Save a sql into a history file
    :param sql: query string
    :param limit: How many queies stores into a history file. Default is 1000
    :return: void
    >>> pass    # Testing in qhistory()
    """
    query_history_csv = os.getenv('JN_UTILS_QUERY_HISTORY', os.getenv('HOME') + os.path.sep + ".ju_qhistory")
    # removing spaces and last ';'
    sql = sql.strip().rstrip(';')
    df_new = pd.DataFrame([[_timestamp(format="%Y%m%d%H%M%S"), sql]], columns=["datetime", "query"])
    df_hist = csv2df(query_history_csv, header=None)
    if df_hist is False:
        df = df_new
    else:
        # If not empty (= same query exists), drop/remove old dupe row(s), so that time will be new.
        df_hist.columns = ["datetime", "query"]
        df_hist_new = df_hist[df_hist['query'].str.lower().isin([sql.lower()]) == False]
        df = df_hist_new.append(df_new, ignore_index=True, sort=False)
    # Currently not appending but overwriting whole file.
    df2csv(df.tail(limit), query_history_csv, mode="w", header=False)


def _autocomp_matcher(text):
    """
    This function is supposed to be a custom matcher for IPython Completer
    TODO: doesn't work (can't register/append in matchers from 'ju' name space)
    :param text:
    :return:
    """
    global _LAST_CONN
    conn = _LAST_CONN
    # Currently only searching table object
    sql_and = " and tbl_name like '" + str(text) + "%'"
    rs = conn.execute("select distinct name from sqlite_master where type = 'table'%s" % (sql_and))
    if bool(rs) is False:
        return
    return _get_col_vals(rs.fetchall(), 0)


def _autocomp_inject(tablename=None):
    """
    Some hack to use autocomplete in the SQL
    TODO: doesn't work any more with newer jupyter lab|notebook
    :param tablename: Optional
    :return: Void
    """
    if bool(tablename):
        tables = [tablename]
    else:
        tables = describe().name.to_list()

    for t in tables:
        cols = describe(t).name.to_list()
        tbl_cls = _gen_class(t, cols)
        try:
            get_ipython().user_global_ns[t] = tbl_cls
            # globals()[t] = tbl_cls
            # locals()[t] = tbl_cls
        except:
            _debug("get_ipython().user_global_ns failed")
            pass


def _gen_class(name, attrs=None, def_value=True):
    if type(attrs) == dict:
        c = type(name, (), attrs)
    else:
        c = type(name, (), {})
        if type(attrs) == list:
            for a in attrs:
                setattr(c, a, def_value)
    return c


def display(df, name=""):
    """
    Wrapper of IPython.display.display
    :param df: A DataFrame object
    :param name: Used when saving into file
    :return Void
    >>> pass
    """
    if bool(name) is False:
        name = _timestamp(format="%Y%m%d%H%M%S%f")
    is_jupyter = True
    try:
        get_ipython()
    except:
        is_jupyter = False
        pass
    if is_jupyter:
        out = IPython.display.HTML(df.to_html())
        IPython.display.display(out)
    else:
        # print(df.to_html())
        df2csv(df=df, file_path="%s.csv" % (str(name)))


def draw(df, width=8, x_col=0, x_colname=None, name="", tail=10):
    """
    Helper function for df.plot()
    As pandas.DataFrame.plot is a bit complicated, using simple options only if this method is used.
    https://pandas.pydata.org/pandas-docs/stable/generated/pandas.DataFrame.plot.html

    :param df: A DataFrame object, which first column will be the 'x' if x_col is not specified
    :param width: This is Inch and default is 16 inch.
    :param x_col: Column index number used for X axis.
    :param x_colname: If column name is given, use this instead of x_col.
    :param name: When saving to file.
    :param tail: To return some sample rows.
    :return: DF (use .tail() or .head() to limit the rows)
    #>>> draw(ju.q("SELECT date, statuscode, bytesSent, elapsedTime from t_request_csv")).tail()
    #>>> draw(ju.q("select QueryHour, SumSqSqlWallTime, SumPostPlanTime, SumSqPostPlanTime from query_stats")).tail()
    >>> pass    # TODO: implement test
    """
    is_jupyter = True
    if bool(name) is False:
        name = _timestamp(format="%Y%m%d%H%M%S%f")
    try:
        get_ipython().run_line_magic('matplotlib', 'inline')
    except:
        is_jupyter = False
        _debug("get_ipython().run_line_magic('matplotlib', 'inline') failed")
        pass
    height_inch = 8
    if len(df) == 0:
        _debug("No rows to draw.")
        return
    if len(df.columns) > 2:
        height_inch = len(df.columns) * 4
    if bool(x_colname) is False:
        x_colname = df.columns[x_col]
    df.plot(figsize=(width, height_inch), x=x_colname, subplots=True, sharex=True)
    if len(name) > 0:
        plt.savefig("%s.png" % (str(name)))
    if is_jupyter:
        plt.show()
    # TODO: x axis doesn't show any legend
    # if len(df) > (width * 2):
    #    interval = int(len(df) / (width * 2))
    #    labels = df[x_colname].tolist()
    #    lables = labels[::interval]
    #    plt.xticks(list(range(interval)), lables)
    return df.tail(tail)


def gantt(df, index_col="", start_col="min_dt", end_col="max_dt", width=8, name="", tail=10):
    """
    Helper function for plt.hlines()
    based on https://stackoverflow.com/questions/31820578/how-to-plot-stacked-event-duration-gantt-charts-using-python-pandas

    :param df: A DataFrame object, which first column will be the 'x' if x_col is not specified
    :param index_col: index column name. default: df.index
    :param start_col: start column name. default: 'min_dt'
    :param end_col: end column name. default: 'max_dt'
    :param width: This is Inch and default is 16 inch.
    :param name: When saving to file.
    :param tail: To return some sample rows.
    :return: DF (use .tail() or .head() to limit the rows)
    >>> pass    # TODO: implement test
    """
    is_jupyter = True
    if bool(name) is False:
        name = _timestamp(format="%Y%m%d%H%M%S%f")
    try:
        get_ipython().run_line_magic('matplotlib', 'inline')
    except:
        is_jupyter = False
        _debug("get_ipython().run_line_magic('matplotlib', 'inline') failed")
        pass
    if len(df) == 0:
        _debug("No rows to draw.")
        return
    df[start_col] = pd.to_datetime(df[start_col])
    df[end_col] = pd.to_datetime(df[end_col])
    fig = plt.figure(figsize=(width, int(len(df) / 3)))
    # TODO: don't know how to change this https://matplotlib.org/3.1.0/api/_as_gen/matplotlib.figure.Figure.html#matplotlib.figure.Figure.add_subplot
    ax = fig.add_subplot(111)
    ax = ax.xaxis_date()
    if index_col is False:
        y = df.index
    else:
        y = df[index_col]
    import matplotlib.dates as mdt
    ax = plt.hlines(y=y, xmin=mdt.date2num(df[start_col]), xmax=mdt.date2num(df[end_col]))
    if len(name) > 0:
        plt.savefig("%s.png" % (str(name)))
    if is_jupyter:
        plt.show()
    return df.tail(tail)


def qhistory(run=None, like=None, html=True, tail=20):
    """
    Return query histories as DataFrame (so that it will be display nicely in Jupyter)
    :param run: Integer of DataFrame row index which will be run
    :param like: String used in 'like' to search 'query' column
    :param html: Whether output in HTML (default) or returning dataframe object
    :param tail: How many last record it displays (default 20)
    :return: Pandas DataFrame contains a list of queries
    >>> import os; os.environ["JN_UTILS_QUERY_HISTORY"] = "/tmp/text_qhistory.csv"
    >>> _save_query("select 1")
    >>> df = qhistory(html=False)
    >>> len(df[df['query'] == 'select 1'])
    1
    >>> _save_query("SELECT 1")
    >>> df = qhistory(html=False)
    >>> len(df)
    1
    >>> os.remove("/tmp/text_qhistory.csv")
    """
    query_history_csv = os.getenv('JN_UTILS_QUERY_HISTORY', os.getenv('HOME') + os.path.sep + ".ju_qhistory")
    df = csv2df(query_history_csv, header=None)
    if df is False or df.empty:
        return
    df.columns = ["datetime", "query"]
    if bool(run):
        sql = df.loc[run, 'query']  # .loc[row_num, column_name]
        _err(sql)
        return query(sql=sql, conn=connect())
    if bool(like):
        df = df[df['query'].str.contains(like)]
    if bool(tail):
        df = df.tail(tail)
    if html is False:
        # TODO: hist(html=False).groupby(['query']).count().sort_values(['count'])
        return df
    current_max_colwitdh = pd.get_option('display.max_colwidth')
    pd.set_option('display.max_colwidth', -1)
    display(df)
    pd.set_option('display.max_colwidth', current_max_colwitdh)


history = qhistory


def describe(tablename=None, colname=None, conn=None):
    """
    Describe a table
    :param tablename: Exact table name. If empty, get table list
    :param colname: String used in like for column name
    :param conn: DB connection (cursor) object
    :return: a DF object contains a table information or table list
    >>> describe(conn=connect())
    Empty DataFrame
    Columns: [name, rootpage]
    Index: []
    """
    if bool(tablename) is False:
        return show_create_table(tablenames=None, like=colname, conn=conn)
    # NOTE: this query is sqlite specific. names = list(map(lambda x: x[0], cursor.description))
    # NOTE2: below query does not work with SQLite older than 3.16
    # select `name`, `type`, `notnull`, `dflt_value`, `pk` from pragma_table_info('%s') where name is not 'index' %s order by cid
    df = query(sql="PRAGMA table_info('%s')" % (tablename), conn=conn, no_history=True)
    if bool(colname) is False:
        return df
    return df.query("name.str.startswith('%s')" % (colname))


desc = describe


def show_create_table(tablenames=None, like=None, conn=None):
    """
    SHOW CREATE TABLE or SHOW TABLES
    :param tablenames: If empty, get table list
    :param like: String used in like, such as column name
    :param conn: DB connection (cursor) object
    :return: void with printing CREATE statement, or a DF object contains table list
    >>> show_create_table(conn=connect())
    Empty DataFrame
    Columns: [name, rootpage]
    Index: []
    """
    if bool(conn) is False: conn = connect()
    sql_and = ""
    if bool(like):
        sql_and = " and sql like '%" + str(like) + "%'"
    if bool(tablenames):
        if isinstance(tablenames, str): tablenames = [tablenames]
        for t in tablenames:
            # Currently searching any object as long as name matches
            rs = conn.execute("select sql from sqlite_master where name = '%s'%s" % (str(t), sql_and))
            if bool(rs) is False:
                continue
            print(rs.fetchall()[0][0])
            # SQLite doesn't like - in a table name. need to escape with double quotes.
            print("Rows: %s\n" % (conn.execute("SELECT count(oid) FROM \"%s\"" % (t)).fetchall()[0][0]))
        return
    if bool(like):
        # Currently only searching table object
        rs = conn.execute("select distinct name from sqlite_master where type = 'table'%s" % (sql_and))
        if bool(rs) is False:
            return
        tablenames = _get_col_vals(rs.fetchall(), 0)
        return show_create_table(tablenames=tablenames)
    return query(
        sql="select distinct name, rootpage from sqlite_master where type = 'table'%s order by rootpage" % (sql_and),
        conn=conn, no_history=True)


def _get_col_vals(matrix, i):
    """
    Get values from the specified column (not table's column, but matrix's column)
    :param matrix: eg: SQL result set
    :param i: column index number, starting from 0
    :return: list contains column values
    >>> _get_col_vals([[1, 2], [2, 3]], 1)
    [2, 3]
    """
    return [row[i] for row in matrix]


def hive_conn(conn_str="jdbc:hive2://localhost:10000/default", user="admin", pwd="admin"):
    """
    Demonstrating Hive connection capability (eventually will merge into connect())
    NOTE: This requires Java 8 (didn't work with Java 9)
    :param conn_str: jdbc:hive2://localhost:10000/default
    :param user: admin
    :param pwd:  admin
    :return: connection (cursor) object
    #>>> hc = hive_conn("jdbc:hive2://localhost:10000/default")
    #>>> hc.execute("SELECT 1")
    #>>> hc.fetchall()
    #[(1,)]
    >>> pass    # TODO: implement test
    """
    cur_dir = os.path.dirname(os.path.abspath(__file__))
    jar_dir = os.path.abspath(os.path.join(cur_dir, '..')) + "/java/hadoop"
    jars = []
    # currently using 1.x versions
    jars += _globr(ptn="hive-jdbc-client-1.*.jar", src=jar_dir, loop=1)
    if len(jars) == 0:
        jars += _globr(ptn="hive-jdbc-1.*-standalone.jar", src=jar_dir, loop=1)
        jars += _globr(ptn="hadoop-core-1.*.jar", src=jar_dir, loop=1)
    _debug("Loading jars: %s ..." % (str(jars)))
    conn = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                              conn_str, [user, pwd], jars).cursor()
    return conn


def run_hive_queries(query_series, conn, output=True):
    """
    Execute multiple queries in a Pandas Series against Hive
    :param query_series: Panda Series object which contains query strings
    :param conn:        Hive connection object (if connection string, every time new connections will be created
    :param output:      Boolean if outputs something or not
    :return:            List of failures
    #>>> df = ju.csv2df(file_path='queries_log_received_distinct.csv', conn=ju.connect())
    #>>> #dfs = ju._chunks(df, 2500)   # May want to split if 'df' is very large, then use _mexec()
    #>>> fails = ju.run_hive_queries(df['extra_lines'], ju.hive_conn("jdbc:hive2://hostname:port/"))
    >>> pass
    """
    failures = []
    for (i, query) in query_series.iteritems():
        error = hive_query_execute(query, conn, i, output)
        if error is not None:
            failures += [{'row': i, 'exception': error, 'query': query}]
    return failures


def hive_query_execute(query, conn, row_num=None, output=False):
    """
    Run one query against Hive
    :param query:   SQL SELECT statement
    :param conn: Hive connection string or object
    :param row_num: Integer, used like ID
    :param output:  Boolean, if True, output results and error
    :return: String: Error message
    #>>> error = ju.hive_query_execute("SELECT 1", ju.hive_conn("jdbc:hive2://hostname:port/"))
    >>> pass
    """
    _time = _timestamp()
    _r = None
    _error = None
    if bool(query) and str(query).lower() != "nan":
        # TODO: should pool the connection, and not sure if it's closing in Jupyter
        try:
            if type(conn) == str:
                conn = hive_conn(conn)
            _r = query_execute(query, conn)
        except Exception as e:
            _error = e
    if output:
        print("### %s at %s ################" % (str(row_num), _time))
        if bool(_error):
            print("\n# Exception happened on No.%s" % (str(row_num)))
            print(query)
            print(_error)
        else:
            print(_r)
    else:
        if str(row_num).isdigit() and (row_num % 100 == 0): sys.stderr.write("\n")
        if bool(_error):
            sys.stderr.write("x")
        else:
            sys.stderr.write(".")
    return _error


def run_hive_queries_multi(query_series, conn_str, num_pool=None, output=False):
    """
    Execute multiple queries in a Pandas Series against Hive
    :param query_series: Panda Series object which contains query strings
    :param conn_str:    As each pool creates own connection, need String
    :param num_pool:    Concurrency number
    :param output:      Boolean if outputs something or not
    :return:            List of failures
    #>>> df = ju.csv2df(file_path='queries_log_received_distinct.csv', conn=ju.connect())
    #>>> #dfs = ju._chunks(df, 2500)   # May want to split if 'df' is very large, then use _mexec()
    #>>> fails = ju.run_hive_queries_multi(df['extra_lines'], "jdbc:hive2://hostname:port/")
    """
    failures = []
    args_list = []
    for (i, query) in query_series.iteritems():
        # from concurrent.futures import ProcessPoolExecutor hangs in Jupyter, so can't use kwargs
        args_list.append((query, conn_str, i, output))
    return _mexec(hive_query_execute, args_list, num=num_pool)


def _massage_tuple_for_save(tpl, long_value="", num_cols=None):
    """
    Transform the given tuple to a DataFrame (or Table columns)
    :param tpl: Tuple which contains values of one row
    :param long_value: multi-lines log messages, like SQL, java stacktrace etc.
    :param num_cols: Number of columns in the table to populate missing column as None/NULL
    :return: modified tuple
    >>> _massage_tuple_for_save(('a','b'), "aaaa", 4)
    ('a', 'b', None, 'aaaa')
    """
    if bool(num_cols) and len(tpl) < num_cols:
        # - 1 for message
        for i in range(((num_cols - 1) - len(tpl))):
            tpl += (None,)
    tpl += (long_value,)
    return tpl


def _insert2table(conn, tablename, tpls, chunk_size=4000):
    """
    Insert one tuple or tuples to a table
    :param conn: Connection object created by connect()
    :param tablename: Table name
    :param tpls: a Tuple or a list of Tuples, which each Tuple contains values for a row
    :return: execute() method result
    #>>> _insert2table(connect(), "test", [('a', 'b', None, 'aaaa')])
    >>> pass    # TODO: implement test
    """
    if isinstance(tpls, list):
        first_obj = tpls[0]
    else:
        first_obj = tpls
        tpls = [tpls]
    chunked_list = _chunks(tpls, chunk_size)
    placeholders = ','.join('?' * len(first_obj))
    for l in chunked_list:
        res = conn.executemany("INSERT INTO " + tablename + " VALUES (" + placeholders + ")", l)
        if bool(res) is False:
            return res
    return res


def _find_matching(line, prev_matches, prev_message, begin_re, line_re, size_re=None, time_re=None, num_cols=None):
    """
    Search one line with given regex (compiled)
    :param line: String of a log line
    :param prev_matches: A tuple which contains previously matched groups
    :param prev_message: String contain log's long text which often multi-lines (eg: SQL, java stacktrace)
    :param begin_re: Compiled regex to find the beginning of the log line
    :param line_re: Compiled regex for group match to get the (column) values
    :param size_re: An optional compiled regex to find size related value
    :param time_re: An optional compiled regex to find time related value
    :param num_cols: Number of columns used in _massage_tuple_for_save() to populate empty columns with Null
    :return: (tuple, prev_matches, prev_message)
    >>> import re;line = "2018-09-04 12:23:45 test";begin_re=re.compile("^\d\d\d\d-\d\d-\d\d");line_re=re.compile("(^\d\d\d\d-\d\d-\d\d).+(test)")
    >>> _find_matching(line, None, None, begin_re, line_re)
    (None, ('2018-09-04',), 'test')
    """
    tmp_tuple = None
    _debug(" - line: %s" % (str(line)))
    # If current line is beginning of a new *log* line (eg: ^2018-08-\d\d...)
    if begin_re.search(line):
        _debug("   matched.")
        # and if previous matches aren't empty, prev_matches is going to be saved
        if bool(prev_matches):
            tmp_tuple = _massage_tuple_for_save(tpl=prev_matches, long_value=prev_message, num_cols=num_cols)
            if bool(tmp_tuple) is False:
                # If some error happened, returning without modifying prev_xxxx
                return (tmp_tuple, prev_matches, prev_message)
            prev_message = None
            prev_matches = None

        _matches = line_re.search(line)
        if _matches:
            # _debug("_matches: %s" % (str(_matches.groups())))
            _tmp_groups = _matches.groups()
            prev_message = _tmp_groups[-1]
            prev_matches = _tmp_groups[:(len(_tmp_groups) - 1)]

            if bool(size_re):
                _size_matches = size_re.search(prev_message)
                if _size_matches:
                    prev_matches += (_size_matches.group(1),)
                else:
                    prev_matches += (None,)
            if bool(time_re):
                _time_matches = time_re.search(prev_message)
                if _time_matches:
                    # _debug(_time_matches.groups())
                    prev_matches += (_ms(_time_matches, time_re),)
                else:
                    prev_matches += (None,)
    else:
        if prev_message is None:
            prev_message = str(line)  # Looks like each line already has '\n'
        else:
            prev_message = str(prev_message) + str(line)  # Looks like each line already has '\n'
    return (tmp_tuple, prev_matches, prev_message)


def _ms(time_matches, time_re_compiled):
    """
    Convert regex match which used _TIME_REGEX to Milliseconds
    :param _time_matches:
    :param time_regex:
    :return: integer
    >>> import re
    >>> time_re = re.compile(_TIME_REGEX)
    >>> prev_message = 'withBundle request for subgroup [subgroup:some_uuid] took [1.03 s] to begin execution'
    >>> _time_matches = time_re.search(prev_message)
    >>> _ms(_time_matches)
    1030.0
    """
    global _TIME_REGEX
    if time_re_compiled.pattern != _TIME_REGEX:
        # If not using default regex, return as string
        return str(time_matches.group(1))
    # Currently not considering micro seconds
    if time_matches.group(2) == "ms":
        return float(time_matches.group(1))
    if time_matches.group(2) == "s":
        return float(time_matches.group(1)) * 1000
    if time_matches.group(2) == "ks":
        return float(time_matches.group(1)) * 1000 * 1000


def _linecount_wc(filepath):
    if filepath.endswith(".gz"):
        return int(os.popen('gunzip -c %s | wc -l' % (filepath)).read().strip())
    return int(os.popen('wc -l %s' % (filepath)).read().split()[0])


def _read_file_and_search(file_path, line_beginning, line_matching, size_regex=None, time_regex=None, num_cols=None,
                          replace_comma=False, line_from=0, line_until=0):
    """
    Read a file and search each line with given regex
    :param file_path: A file path
    :param line_beginning: Regex to find the beginning of the line (normally like ^2018-08-21)
    :param line_matching: Regex to capture column values
    :param size_regex: Regex to capture size
    :param time_regex: Regex to capture time/duration
    :param num_cols: Number of columns
    :param replace_comma: Sqlite does not like comma in datetime with milliseconds
    :param line_from: Read line from
    :param line_until: Read line until
    :return: A list of tuples
    >>> pass    # TODO: implement test
    """
    _debug(f"line_beginning: {line_beginning}")
    begin_re = re.compile(line_beginning)
    line_re = re.compile(line_matching)
    size_re = re.compile(size_regex) if bool(size_regex) else None
    time_re = re.compile(time_regex) if bool(time_regex) else None
    prev_matches = None
    prev_message = None
    tuples = []
    time_with_ms = re.compile('\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d,\d+')

    ttl_line = _linecount_wc(file_path)
    tmp_counter = int(float(ttl_line) / 10)
    connter = 10000 if tmp_counter < 10000 else tmp_counter
    filename = os.path.basename(file_path)
    f = _open_file(file_path)
    # Read lines
    _ln = 0
    _empty = 0
    for l in f:
        _ln += 1
        # _debug("  _ln=%s, line_from=%s line_until=%s ..." % (str(_ln), str(line_from), str(line_until)))
        if bool(line_from) and _ln < line_from:
            _empty += 1
            continue
        if bool(line_until) and _ln > line_until:
            _empty += 1
            continue
        if (_ln % connter) == 0:
            _err("  Processed %s/%s (skip:%s) lines for %s (%s) ..." % (
                str(_ln), ttl_line, str(_empty), filename, _timestamp(format="%H:%M:%S")))
        if bool(l) is False:
            break  # most likely the end of the file
        (tmp_tuple, prev_matches, prev_message) = _find_matching(line=l, prev_matches=prev_matches,
                                                                 prev_message=prev_message, begin_re=begin_re,
                                                                 line_re=line_re, size_re=size_re, time_re=time_re,
                                                                 num_cols=num_cols)
        if bool(tmp_tuple):
            if replace_comma and time_with_ms.search(tmp_tuple[0]):
                tmp_l = list(tmp_tuple)
                tmp_l[0] = tmp_tuple[0].replace(",", ".")
                tmp_tuple = tuple(tmp_l)
            tuples += [tmp_tuple]
        else:
            _empty += 1
    f.close()

    # append last message (last line)
    if bool(prev_matches):
        tuples += [_massage_tuple_for_save(tpl=prev_matches, long_value=prev_message, num_cols=num_cols)]
    return tuples


def threads2table(filename="threads.txt", tablename=None, conn=None, date_time=None):
    # TODO: date_time (should use file modified time? but not trust-able)
    # TODO: waiting on | locked
    return logs2table(filename=filename, tablename=tablename, conn=conn,
                      col_names=['thread_name', 'id', 'state', 'stacktrace'],
                      line_beginning="^\"",
                      line_matching='^"([^"]+)" id=([^ ]+) state=(\w+)(.*)',
                      size_regex=None, time_regex=None)


def logs2table(filename, tablename=None, conn=None,
               col_names=['date_time', 'loglevel', 'thread', 'user', 'class', 'message'],
               num_cols=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
               line_matching="^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]+) - (.*)",
               size_regex=None, time_regex=None,
               line_from=0, line_until=0,
               max_file_num=10, max_file_size=(1024 * 1024 * 100),
               appending=False, multiprocessing=False):
    """
    Insert multiple log files into *one* table
    :param filename: a file name (or path) or *simple* glob regex
    :param tablename: Table name. If empty, generated from filename
    :param conn:  Connection object (ju.connect())
    :param col_names: Column definition list or dict (column_name1 data_type, column_name2 data_type, ...)
    :param num_cols: Number of columns in the table. Optional if col_def_str is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param line_from: Read line from
    :param line_until: Read line until
    :param max_file_num: To avoid memory issue, setting max files to import
    :param max_file_size: To avoid memory issue, setting max file size per file
    :param appending: default is False. If False, use 'DROP TABLE IF EXISTS'
    :param multiprocessing: (Experimental) default is False. If True, use multiple CPUs
    :return: True if no error, or a tuple contains multiple information for debug
    #>>> logs2table(filename='queries.*log*', tablename='t_queries_log',
            col_names=['date_time', 'ids', 'message', 'extra_lines'],
            line_matching='^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) (\{.*?\}) - ([^:]+):(.*)',
            size_regex=None, time_regex=None)
    #>>> logs2table(filename='nexus.log*', tablename='t_nexus_log',
         col_names=['date_time', 'loglevel', 'thread', 'user', 'class', 'message'],
            line_matching='^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]+) - (.*)',
            size_regex=None, time_regex=None)
    #>>> logs2table('clm-server_*.log*', tablename="t_clm_server_log", multiprocessing=True, max_file_num=20
            col_names=['date_time', 'loglevel', 'thread', 'user', 'class', 'message'],
            line_matching='^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]+) - (.*)',
            size_regex=None, time_regex=None)
    >>> pass    # TODO: implement test
    """
    global _SIZE_REGEX
    global _TIME_REGEX
    if bool(conn) is False: conn = connect()

    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_cols) is False:
        num_cols = len(col_names)
    if os.path.exists(filename):
        files = [filename]
    else:
        files = _globr(filename)

    if bool(files) is False:
        # _err("No file by searching with %s ..." % (str(filename)))
        return False

    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (filename, str(len(files))))

    col_def_str = ""
    if isinstance(col_names, dict):
        for k, v in col_names.iteritems():
            if col_def_str != "":
                col_def_str += ", "
            col_def_str += "%s %s" % (k, v)
    else:
        for v in col_names:
            if col_def_str != "":
                col_def_str += ", "
            # the column name 'jsonstr' is currently not in use.
            if v == 'jsonstr':
                col_def_str += "%s json" % (v)
            elif v == 'size' and size_regex == _SIZE_REGEX:
                col_def_str += "%s INTEGER" % (v)
            elif v == 'time' and time_regex == _TIME_REGEX:
                col_def_str += "%s REAL" % (v)
            else:
                col_def_str += "%s TEXT" % (v)

    if bool(tablename) is False:
        first_filename = os.path.basename(files[0])
        tablename = _pick_new_key(first_filename, {}, using_1st_char=False, prefix='t_')

    # If not None, create a table
    if bool(col_def_str):
        if appending is False:
            res = conn.execute("DROP TABLE IF EXISTS %s" % (tablename))
            if bool(res) is False:
                return res
            _err("Drop if exists and Creating table: %s ..." % (str(tablename)))
        else:
            _err("Creating table: %s ..." % (str(tablename)))
        res = conn.execute("CREATE TABLE IF NOT EXISTS %s (%s)" % (tablename, col_def_str))
        if bool(res) is False:
            return res

    if multiprocessing:
        args_list = []
        for f in files:
            if os.stat(f).st_size >= max_file_size:
                _err("WARN: File %s (%d MB) is too large (max_file_size=%d)" % (
                    str(f), int(os.stat(f).st_size / 1024 / 1024), max_file_size))
                continue
            # concurrent.futures.ProcessPoolExecutor hangs in Jupyter, so can't use kwargs
            args_list.append(
                (f, line_beginning, line_matching, size_regex, time_regex, num_cols, True, line_from, line_until))
        # file_path, line_beginning, line_matching, size_regex=None, time_regex=None, num_cols=None, replace_comma=False
        rs = _mexec(_read_file_and_search, args_list)
        for tuples in rs:
            if bool(tuples) is False or len(tuples) == 0:
                _err("WARN: _mexec returned empty tuple ...")
                continue
            res = _insert2table(conn=conn, tablename=tablename, tpls=tuples)
            if bool(res) is False:  # if fails once, stop
                _err("_insert2table failed to insert %d ..." % (len(tuples)))
                return res
    else:
        for f in files:
            if os.stat(f).st_size >= max_file_size:
                _err("WARN: File %s (%d MB) is too large (max_file_size=%d)" % (
                    str(f), int(os.stat(f).st_size / 1024 / 1024), max_file_size))
                continue
            tuples = _read_file_and_search(file_path=f, line_beginning=line_beginning, line_matching=line_matching,
                                           size_regex=size_regex, time_regex=time_regex, num_cols=num_cols,
                                           replace_comma=True, line_from=line_from, line_until=line_until)
            if bool(tuples):
                _debug(("tuples len:%d" % len(tuples)))
            if len(tuples) > 0:
                res = _insert2table(conn=conn, tablename=tablename, tpls=tuples)
                if bool(res) is False:  # if fails once, stop
                    return res
    _autocomp_inject(tablename=tablename)
    return True


def logs2dfs(filename, col_names=['datetime', 'loglevel', 'thread', 'ids', 'size', 'time', 'message'],
             num_fields=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
             line_matching="^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[0-9.,]*) (.+?) \[(.+?)\] (\{.*?\}) (.+)",
             size_regex=_SIZE_REGEX, time_regex=_TIME_REGEX,
             max_file_num=10, multiprocessing=False):
    """
    Convert multiple files to *multiple* DataFrame objects
    :param filename: A file name or *simple* regex used in glob to select files.
    :param col_names: Column definition list or dict (column_name1 data_type, column_name2 data_type, ...)
    :param num_fields: Number of columns in the table. Optional if col_def_str is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param max_file_num: To avoid memory issue, setting max files to import
    :param multiprocessing: (Experimental) If True, use multiple CPUs
    :return: A concatenated DF object
    #>>> df = logs2dfs(filename="debug.2018-08-28.11.log.gz")
    #>>> df2 = df[df.loglevel=='DEBUG'].head(10)
    #>>> bool(df2)
    #True
    >>> pass    # TODO: implement test
    """
    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_fields) is False:
        num_fields = len(col_names)
    files = _globr(filename)

    if bool(files) is False:
        return False

    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (filename, str(len(files))))

    dfs = []
    if multiprocessing:
        args_list = []
        for f in files:
            args_list.append((f, line_beginning, line_matching, size_regex, time_regex, num_fields, True))
        # from concurrent.futures import ProcessPoolExecutor hangs in Jupyter, so can't use kwargs
        rs = _mexec(_read_file_and_search, args_list)
        for tuples in rs:
            if len(tuples) > 0:
                dfs += [pd.DataFrame.from_records(tuples, columns=col_names)]
    else:
        for f in files:
            _err("Processing %s (%d KB) ..." % (str(f), os.stat(f).st_size / 1024))
            tuples = _read_file_and_search(file_path=f, line_beginning=line_beginning, line_matching=line_matching,
                                           size_regex=size_regex, time_regex=time_regex, num_cols=num_fields,
                                           replace_comma=True)
            if len(tuples) > 0:
                dfs += [pd.DataFrame.from_records(tuples, columns=col_names)]
    _err("Completed.")
    if bool(dfs) is False:
        return None
    return pd.concat(dfs, sort=False)


def _gen_regex_for_request_logs(filename="request.log"):
    """
    Return a list which contains column names, and regex pattern for request.log
    :param filename: A file name or *simple* regex used in glob to select files.
    :return: (col_list, pattern_str)
    """
    files = _globr(filename)
    if bool(files) is False:
        return ([], "")
    checking_line = linecache.getline(files[0], 2)  # first line can be a junk: "** TRUNCATED ** linux x64"
    # @see: samples/bash/log_search.sh:f_request2csv()
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent", "elapsedTime", "headerUserAgent", "thread"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)" \[([^\]]+)\]'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "headerUserAgent", "thread"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)" \[([^\]]+)\]'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "headerUserAgent"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([0-9]+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)

    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "misc"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    else:
        _err("Can not determine the log format for %s . Using last one." % (str(files[0])))
        return (columns, partern_str)


def _gen_regex_for_app_logs(filename="nexus.log"):
    """
    Return a list which contains column names, and regex pattern for nexus.log, clm-server.log, server.log
    :param filename: A file name or *simple* regex used in glob to select files.
    :param checking_line: Based on this line, columns and regex will be decided
    :return: (col_list, pattern_str)
    2020-01-03 00:00:38,357-0600 WARN  [qtp1359575796-407871] anonymous org.sonatype.nexus.proxy.maven.maven2.M2GroupRepository - IOException during parse of metadata UID="oracle:/junit/junit-dep/maven-metadata.xml", will be skipped from aggregation!
    """
    files = _globr(filename)
    if bool(files) is False:
        return ([], "")

    # Default and in case can't be identified
    columns = ['date_time', 'loglevel', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +(.+)'

    for i in range(1, 10):
        checking_line = linecache.getline(files[0], i)
        if re.search('^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*)', checking_line):
            break
    if bool(checking_line) is False:
        _err("Could not determine columns and pattern_str. Using default.")
        return (columns, partern_str)
    _debug(checking_line)

    columns = ['date_time', 'loglevel', 'thread', 'node', 'user', 'class', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]*) ([^ ]+) - (.*)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ['date_time', 'loglevel', 'thread', 'user', 'class', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]+) - (.*)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    return (columns, partern_str)


def _gen_regex_for_hazel_health(sample):
    """
    Return a list which contains column names, and regex pattern for nexus.log, clm-server.log, server.log
    :param sample: A sample line
    :return: (col_list, pattern_str)
    """
    # no need to add 'date_time'
    columns = ['ip', 'port', 'user', 'cluster_ver']
    cols_tmp = re.findall(r'([^ ,]+)=', sample)
    # columns += list(map(lambda x: x.replace('.', '_'), cols_tmp))
    columns += cols_tmp
    partern_str = '^\[([^\]]+)]:([^ ]+) \[([^\]]+)\] \[([^\]]+)\]'
    for c in cols_tmp:
        partern_str += " %s=([^, ]+)," % (c)
    partern_str += "?"
    return (columns, partern_str)


def load_csvs(src="./", conn=None, include_ptn='*.csv', exclude_ptn='', chunksize=1000):
    """
    Convert multiple CSV files to DF and DB tables
    Example: _=ju.load_csvs("./", ju.connect(), "tables_*.csv")
    :param src: Source directory path
    :param conn: DB connection object
    :param include_ptn: Include pattern
    :param exclude_ptn: Exclude pattern
    :param chunksize: to_sql() chunk size
    :return: A tuple contain key=>file relationship and Pandas dataframes objects
    #>>> (names_dict, dfs) = load_csvs(src="./stats")
    #>>> bool(names_dict)
    #True
    >>> pass    # TODO: implement test
    """
    names_dict = {}
    dfs = {}
    ex = re.compile(exclude_ptn)

    files = _globr(include_ptn, src)
    for f in files:
        if bool(exclude_ptn) and ex.search(os.path.basename(f)): continue

        f_name, f_ext = os.path.splitext(os.path.basename(f))
        new_name = _pick_new_key(f_name, names_dict, using_1st_char=(bool(conn) is False), prefix='t_')
        _err("Creating table: %s ..." % (new_name))
        names_dict[new_name] = f

        dfs[new_name] = csv2df(file_path=f, conn=conn, tablename=new_name, chunksize=chunksize)
    return (names_dict, dfs)


def csv2df(filename, conn=None, tablename=None, chunksize=1000, header=0):
    '''
    Load a CSV file into a DataFrame
    If conn is given, import into a DB table
    :param filename: file path or file name or glob string
    :param conn: DB connection object. If not empty, import into a sqlite table
    :param tablename: If empty, table name will be the filename without extension
    :param chunksize: Rows will be written in batches of this size at a time
    :param header: Row number(s) to use as the column names if not the first line (0) is not column name
                   Or a list of column names
    :return: Pandas DF object or False if file is not readable
    #>>> df = ju.csv2df(file_path='./slow_queries.csv', conn=ju.connect())
    >>> pass    # Testing in df2csv()
    '''
    global _DB_SCHEMA
    if os.path.exists(filename):
        file_path = filename
    else:
        files = _globr(filename)
        if bool(files) is False:
            _err("No file found from: %s ..." % (str(filename)))
            return False
        file_path = files[0]

    names = None
    if type(header) == list:
        names = header
        header = None
    df = pd.read_csv(file_path, escapechar='\\', header=header, names=names)
    if bool(tablename) and bool(conn) is False:
        conn = connect()
    if bool(conn):
        if bool(tablename) is False:
            tablename = _pick_new_key(os.path.basename(file_path), {}, using_1st_char=False, prefix='t_')
        _err("Creating table: %s ..." % (tablename))
        # Not sure if to_sql returns some result
        df.to_sql(name=tablename, con=conn, chunksize=chunksize, if_exists='replace', schema=_DB_SCHEMA)
        _autocomp_inject(tablename=tablename)
        return len(df) > 0
    return df


def obj2csv(obj, file_path, mode="w", header=True):
    '''
    Save a python object to a CSV file
    :param obj: Pandas Data Frame object or list or dict
    :param file_path: File Path
    :param mode: mode used with open(). Default 'w'
    :return: unknown (what to_csv returns)
    >>> pass
    '''
    # [{"col1":1, "col2":2}, {"col1":3, "col2":4}]
    if type(obj) == type([]):
        df = pd.DataFrame(obj)
    elif type(obj) == type({}):
        df = pd.DataFrame.from_dict(obj)
    elif type(obj) == pd.core.frame.DataFrame:
        df = obj
    else:
        _err("Unsupported type: %s" % str(type(obj)))
        return
    return df2csv(df, file_path, mode=mode, header=header)


def df2csv(df, file_path, mode="w", header=True):
    '''
    Save DataFrame to a CSV file
    :param df: Pandas Data Frame object
    :param file_path: File Path
    :param mode: mode used with open(). Default 'w'
    :return: unknown (what to_csv returns)
    >>> import pandas as pd
    >>> df = pd.DataFrame([{"key":"a", "val":"value"}])
    >>> df2csv(df, '/tmp/test_df2csv.csv', 'w')
    >>> df2 = csv2df('/tmp/test_df2csv.csv')
    >>> df == df2
        key   val
    0  True  True
    '''
    return df.to_csv(file_path, mode=mode, header=header, index=False, escapechar='\\')


def df2files(df, filepath_prefix, extension="", columns=None, overwriting=False, sep="="):
    """
    Write each line/row of a DataFrame into individual file
    :param df: Panda DataFrame
    :param filepath_prefix: filename will be this one + index + extension (if not empty)
    :param extension: file extension (eg: ".txt" or just "txt")
    :param columns: list of column names or string
    :param overwriting: if True, the destination file will be overwritten
    :param sep: Separator character which is used when multiple columns exist in the Series
    :return: None/Void
    #>>> df2files(queries_df, "test_", ".sql", ['extra_lines']) # generate a="xxxxx"
    #>>> df2files(queries_df, "test_", ".sql", "extra_lines")   # generate xxxxx
    >>> pass
    """
    if len(df) < 1:
        return False
    if type(columns) == type([]) and len(columns) > 0:
        _df = df[columns]
    else:
        _df = df
    for i, row in _df.iterrows():
        if len(extension) > 0:
            full_filepath = filepath_prefix + str(i) + "." + extension.lstrip(".")
        else:
            full_filepath = filepath_prefix + str(i)
        if overwriting is False and os.path.exists(full_filepath):
            _err("%s exists. Skipping ..." % (full_filepath))
            continue
        _err("Writing index=%s into %s ..." % (str(i), full_filepath))
        with open(full_filepath, 'w') as f2:
            if type(columns) == type('a'):
                f2.write(row[columns])
            else:
                f2.write(row.to_csv(sep=sep))


def analyse_logs(start_isotime=None, end_isotime=None, elapsed_time=0, tail_num=10000):
    """
    A prototype function to analyse log files (expecting request.log converted to request.csv)
    TODO: cleanup later
    :param start_isotime:
    :param end_isotime:
    :param elapsed_time:
    :param tail_num:
    :return: void
    >>> pass    # test should be done in each function
    """
    ## Audit json if exist
    _ = json2df('audit.json', tablename="t_audit_logs", json_cols=['attributes', 'data'], conn=connect())

    ## Request.*csv* exists, use that (because it's faster), if not, logs2table, which is slower.
    result = csv2df('request.csv', tablename="t_request_logs", conn=connect())
    if bool(result) is False:
        (col_names, line_matching) = _gen_regex_for_request_logs('request.log')
        result = logs2table('request.log', tablename="t_request_logs", col_names=col_names, line_beginning="^.",
                            line_matching=line_matching)
    if bool(result):
        where_sql = "WHERE 1=1"
        if bool(elapsed_time) is True:
            where_sql += " AND elapsedTime >= %d" % (elapsed_time)
        if bool(start_isotime) is True:
            where_sql += " AND UDF_STR2SQLDT(`date`, '%d/%b/%Y:%H:%M:%S %z') >= UDF_STR2SQLDT('" + start_isotime + " +0000','%Y-%m-%d %H:%M:%S %z')"
        if bool(end_isotime) is True:
            where_sql += " AND UDF_STR2SQLDT(`date`, '%d/%b/%Y:%H:%M:%S %z') <= UDF_STR2SQLDT('" + end_isotime + " +0000','%Y-%m-%d %H:%M:%S %z')"
        query = """SELECT UDF_REGEX('(\d\d/[a-zA-Z]{3}/20\d\d:\d\d)', `date`, 1) AS date_hour, statusCode,
    CAST(MAX(CAST(elapsedTime AS INT)) AS INT) AS max_elaps, 
    CAST(MIN(CAST(elapsedTime AS INT)) AS INT) AS min_elaps, 
    CAST(AVG(CAST(elapsedTime AS INT)) AS INT) AS avg_elaps, 
    CAST(AVG(CAST(bytesSent AS INT)) AS INT) AS avg_bytes, 
    count(*) AS occurrence
FROM t_request_logs
%s
GROUP BY 1, 2""" % (where_sql)
        name = "request_log-hourly_aggs"
        _err("Query (%s): \n%s" % (name, query))
        display(q(query), name=name)
        query = """SELECT UDF_STR2SQLDT(`date`, '%%d/%%b/%%Y:%%H:%%M:%%S %%z') AS date_time, 
    CAST(statusCode AS INTEGER) AS statusCode, 
    CAST(bytesSent AS INTEGER) AS bytesSent, 
    CAST(elapsedTime AS INTEGER) AS elapsedTime 
FROM t_request_logs %s""" % (where_sql)
        name = "request_log-status_bytesent_elapsed"
        _err("Query (%s): \n%s" % (name, query))
        draw(q(query).tail(tail_num), name=name)

    ## Loading application log file(s) into database.
    (col_names, line_matching) = _gen_regex_for_app_logs('nexus.log')
    nxrm_logs = logs2table('nexus.log', tablename="t_logs", col_names=col_names, line_matching=line_matching)
    (col_names, line_matching) = _gen_regex_for_app_logs('*server.log')
    nxiq_logs = logs2table('*server.log', tablename="t_logs", col_names=col_names, line_matching=line_matching)

    # Hazelcast health monitor
    # if "health_monitor.json" exists:
    #   result = ju.json2df('health_monitor.json', tablename="t_health_monitor", conn=ju.connect())
    #   query = """select date_time, xxxx from t_health_monitor"""
    #   ju.draw(ju.q(query))
    if bool(nxrm_logs):
        _err("Generating t_health_monitor from t_logs ...")
        df_hm = q("""select date_time, message from t_logs
    where loglevel = 'INFO'
    and class = 'com.hazelcast.internal.diagnostics.HealthMonitor'""")
        if len(df_hm) > 0:
            (col_names, line_matching) = _gen_regex_for_hazel_health(df_hm['message'][1])
            msg_ext = df_hm['message'].str.extract(line_matching)
            msg_ext.columns = col_names
            # Delete unnecessary column(s), then left join the extracted dataframe, then load into SQLite
            df_hm.drop(columns=['message']).join(msg_ext).to_sql(name="t_health_monitor", con=connect(), chunksize=1000,
                                                                 if_exists='replace', schema=_DB_SCHEMA)
            _autocomp_inject(tablename='t_health_monitor')
            where_sql = "WHERE 1=1"
            if bool(start_isotime) is True:
                where_sql += " AND date_time >= '" + start_isotime + "'"
            if bool(end_isotime) is True:
                where_sql += " AND date_time <= '" + end_isotime + "'"
            query = """select date_time
    , UDF_STR_TO_INT(`physical.memory.free`) as sys_mem_free_bytes
    --, UDF_STR_TO_INT(`swap.space.free`) as swap_free_bytes
    , CAST(`swap.space.free` AS INTEGER) as swap_free_bytes
    , UDF_STR_TO_INT(`heap.memory.used/max`) as heap_used_percent
    , CAST(`major.gc.count` AS INTEGER) as majour_gc_count
    , UDF_STR_TO_INT(`major.gc.time`) as majour_gc_msec
    , CAST(`load.process` AS REAL) as load_proc_percent
    , CAST(`load.system` AS REAL) as load_sys_percent
    , CAST(`load.systemAverage` AS REAL) as load_system_avg
    , CAST(`thread.count` AS INTEGER) as thread_count
    , CAST(`connection.active.count` AS INTEGER) as node_conn_count
FROM t_health_monitor
%s""" % (where_sql)
            name = "nexus_health_monitor"
            _err("Query (%s): \n%s" % (name, query))
            draw(q(query), name=name)

    # Nexus IQ
    if bool(nxiq_logs):
        # below queries are not so good, so not executing at this moment.
        query = """SELECT thread, min(date_time), max(date_time), 
    STRFTIME('%s', UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d+)', max(date_time), 1))
  - STRFTIME('%s', UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d+)', min(date_time), 1)) as diff,
    count(*)
FROM t_logs
WHERE thread LIKE 'PolicyEvaluateService%'
GROUP BY 1
ORDER BY diff, thread"""
        name = "nxiq_log-policy_scan_aggs"
        # _err("Query (%s): \n%s" % (name,query))
        # display(q(query), name=name)
        query = """SELECT date_time, 
  UDF_REGEX(' in (\d+) ms', message, 1) as ms,
  UDF_REGEX('ms. (\d+)$', message, 1) as status
FROM t_logs
WHERE t_logs.class = 'com.sonatype.insight.brain.hds.HdsClient'
  AND t_logs.message LIKE 'Completed request%'"""
        name = "nxiq_log-hdfsclient_results"
        # _err("Query (%s): \n%s" % (name,query))
        # display(q(query), name=name)

        query = """SELECT date_time, thread,
    UDF_REGEX(' scan id ([^ ]+),', message, 1) as scan_id,
    CAST(UDF_REGEX(' in (\d+) ms', message, 1) as INT) as ms 
FROM t_logs
WHERE t_logs.message like 'Evaluated policy for%'
ORDER BY ms DESC
LIMIT 10"""
        name = "nxiq_log-top10_slow_scan"
        _err("Query (%s): \n%s" % (name, query))
        display(q(query), name="nxiq_log-top10_slow_scan")

    if bool(nxrm_logs) or bool(nxiq_logs):
        ## analyse t_logs table (eg: cout ERROR|WARN)
        query = """SELECT UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d)', date_time, 1) as date_hour, loglevel, count(1) 
    FROM t_logs
    %s
      AND loglevel NOT IN ('TRACE', 'DEBUG', 'INFO')
    GROUP BY 1, 2""" % (where_sql)
        name = "warn_error_hourly"
        _err("Query (%s): \n%s" % (name, query))
        draw(q(query), name=name)

    # TODO: analyse db job triggers
    # q("""SELECT description, fireInstanceId
    # , nextFireTime
    # , DATETIME(ROUND(nextFireTime / 1000), 'unixepoch') as NextAt
    # , DATETIME(ROUND(previousFireTime / 1000), 'unixepoch') as PrevAt
    # , DATETIME(ROUND(startTime / 1000), 'unixepoch') as startAt
    # , jobDataMap, cronEx
    # FROM t_db_job_triggers_json
    # WHERE nextFireTime is NOT NULL
    #  AND nextFireTime > 1578290830000
    # ORDER BY nextFireTime
    # """)
    _err("Completed.")


def load(jsons_dir=["./engine/aggregates", "./engine/cron-scheduler"], csvs_dir="./stats",
         jsons_exclude_ptn='physicalPlans|partition|incremental|predictions', csvs_exclude_ptn=''):
    """
    Deprecated
    Execute loading functions (currently load_jsons and load_csvs)
    :param jsons_dir: (optional) Path to a directory which contains JSON files
    :param csvs_dir: (optional) Path to a directory which contains CSV files
    :param jsons_exclude_ptn: (optional) Regex to exclude some tables when reading JSON files
    :param csvs_exclude_ptn: (optional) Regex to exclude some tables when reading CSV files
    :return: void
    >>> pass    # test should be done in load_jsons and load_csvs
    """
    # TODO: shouldn't have any paths in here but should be saved into some config file.
    if type(jsons_dir) == list:
        for jd in jsons_dir:
            load_jsons(jd, connect(), exclude_ptn=jsons_exclude_ptn)
    else:
        load_jsons(jsons_dir, connect(), exclude_ptn=jsons_exclude_ptn)

    if type(csvs_dir) == list:
        for cd in csvs_dir:
            load_csvs(cd, connect(), exclude_ptn=csvs_exclude_ptn)
    else:
        load_csvs(csvs_dir, connect(), exclude_ptn=csvs_exclude_ptn)
    _autocomp_inject()
    _err("Completed.")


def update_check(file=None, baseurl="https://raw.githubusercontent.com/hajimeo/samples/master/python"):
    """
    (almost) Alias of update()
    Check if update is avaliable (actually checking file size only at this moment)
    :param file: File path string. If empty, checks for this file (jn_utils.py)
    :param baseurl: Default is https://raw.githubusercontent.com/hajimeo/samples/master/python
    :return: If update available, True and output message in stderr)
    >>> b = update_check()
    >>> b is not False
    True
    """
    return update(file, baseurl, check_only=True)


def update(file=None, baseurl="https://raw.githubusercontent.com/hajimeo/samples/master/python", check_only=False,
           force_update=False):
    """
    Update the specified file from internet
    :param file: File path string. If empty, updates for this file (jn_utils.py)
    :param baseurl: Default is https://raw.githubusercontent.com/hajimeo/samples/master/python
    :param check_only: If True, do not update but check only
    :param force_update: Even if same size, replace the file
    :return: None if successfully replaced or don't need to update
    >>> pass
    """
    if bool(file) is False:
        file = __file__
    # i'm assuming i do not need to concern of .pyc...
    filename = os.path.basename(file)
    url = baseurl.rstrip('/') + "/" + filename
    remote_size = int(urlopen(url).headers["Content-Length"])
    local_size = int(os.path.getsize(file))
    if remote_size < (local_size / 2):
        _err("Couldn't check the size of %s" % (url))
        return False
    if force_update is False and int(remote_size) == int(local_size):
        # If exactly same size, not updating
        _err("No need to update %s" % (filename))
        return
    if int(remote_size) != int(local_size):
        _err("%s size is different between remote (%s KB) and local (%s KB)." % (
            filename, int(remote_size / 1024), int(local_size / 1024)))
        if check_only:
            _err("To update, use 'ju.update()'\n")
            return True
    new_file = "/tmp/" + filename + "_" + _timestamp(format="%Y%m%d%H%M%S")
    os.rename(file, new_file)
    remote_content = urlopen(url).read()
    with open(file, 'wb') as f:
        f.write(remote_content)
    _err("%s was updated and back up is %s" % (filename, new_file))
    return


def help(func_name=None):
    """
    Output help information
    :param func_name: (optional) A function name written in this script
    :return: void
    >>> pass
    """
    import jn_utils as ju
    if bool(func_name):
        m = getattr(ju, func_name, None)
        if callable(m) and hasattr(m, '__doc__') and len(str(m.__doc__)) > 0:
            print(func_name + ":")
            print(m.__doc__)
        return
    print(ju.__doc__)
    print("Available functions:")
    for attr_str in dir(ju):
        if attr_str.startswith("_"): continue
        # TODO: no idea why those functions matches if condition.
        if attr_str in ['create_engine', 'datetime', 'help']: continue
        m = getattr(ju, attr_str, None)
        if callable(m) and hasattr(m, '__doc__') and bool(m.__doc__):
            print("    " + attr_str)
    print("For a function help, use 'ju.help(\"function_name\")'.")


if __name__ == '__main__':
    import doctest

    doctest.testmod(verbose=True)
