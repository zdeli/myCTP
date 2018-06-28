# encoding: UTF-8

"""
包含一些开发中常用的函数
"""

import os,sys,subprocess
import socket
import decimal
import json
import re
import traceback
from shutil import copyfile
from datetime import datetime
from math import isnan

import pandas as pd
import MySQLdb
from pandas.io import sql
import pymysql
from sqlalchemy import create_engine

from vnpy.trader.vtGlobal import globalSetting

## ==================================
## 发送邮件通知
import smtplib
from email.mime.text import MIMEText
from email.header import Header
import codecs
## ==================================

MAX_NUMBER  = 10000000000000
MAX_DECIMAL = 4

#----------------------------------------------------------------------
cpdef safeUnicode(value):
    """检查接口数据潜在的错误，保证转化为的字符串正确"""
    # 检查是数字接近0时会出现的浮点数上限
    if type(value) is int or type(value) is float:
        if value > MAX_NUMBER or isnan(value):
            value = 0
    
    # 检查防止小数点位过多
    if type(value) is float:
        d = decimal.Decimal(str(value))
        if abs(d.as_tuple().exponent) > MAX_DECIMAL:
            value = round(value, ndigits=MAX_DECIMAL)
    
    return unicode(value)


#----------------------------------------------------------------------
cpdef todayDate():
    """获取当前本机电脑时间的日期"""
    return datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)    


# 图标路径
iconPathDict = {}

## =============================================================================
import inspect
if not hasattr(sys.modules[__name__], '__file__'):
    __file__ = inspect.getfile(inspect.currentframe())

path = os.path.abspath(os.path.dirname(__file__))
## =============================================================================
for root, subdirs, files in os.walk(path):
    for fileName in files:
        if '.ico' in fileName:
            iconPathDict[fileName] = os.path.join(root, fileName)

path = os.getcwd()      # 遍历工作目录
for root, subdirs, files in os.walk(path):
    for fileName in files:
        if '.ico' in fileName:
            iconPathDict[fileName] = os.path.join(root, fileName)

#----------------------------------------------------------------------
cpdef loadIconPath(iconName):
    """加载程序图标路径"""   
    global iconPathDict
    return iconPathDict.get(iconName, '')    
    


#----------------------------------------------------------------------
cpdef getTempPath(name, subdir = ''):
    """获取存放临时文件的路径"""
    if subdir:
        tempPath = os.path.join(os.getcwd(), 'temp', subdir)
    else:
        tempPath = os.path.join(os.getcwd(), 'temp')
    if not os.path.exists(tempPath):
        os.makedirs(tempPath)
        
    path = os.path.join(tempPath, name)
    return path

## -----------------------------------------------------------------------------
cpdef getLogPath(name):
    """获取存放临时文件的路径"""
    logPath = os.path.join(os.getcwd(), 'trading/log')
    if not os.path.exists(logPath):
        os.makedirs(logPath)

    path = os.path.join(logPath, name)
    return path

# JSON配置文件路径
jsonPathDict = {}

#----------------------------------------------------------------------
cpdef getJsonPath(name, moduleFile):
    """
    获取JSON配置文件的路径：
    1. 优先从当前工作目录查找JSON文件
    2. 若无法找到则前往模块所在目录查找
    """
    currentFolder = os.getcwd()
    currentJsonPath = os.path.join(currentFolder, name)
    if os.path.isfile(currentJsonPath):
        jsonPathDict[name] = currentJsonPath
        return currentJsonPath
    
    moduleFolder = os.path.abspath(os.path.dirname(moduleFile))
    moduleJsonPath = os.path.join(moduleFolder, '.', name)
    jsonPathDict[name] = moduleJsonPath
    return moduleJsonPath


# 加载全局配置
#----------------------------------------------------------------------
cpdef loadJsonSetting(settingFileName):
    """加载JSON配置"""
    settingFilePath = getJsonPath(settingFileName, __file__)

    setting = {}

    try:
        with open(settingFilePath, 'rb') as f:
            setting = f.read()
            if type(setting) is not str:
                setting = str(setting, encoding='utf8')
            setting = json.loads(setting)
    except:
        traceback.print_exc()
    
    return setting

## =========================================================================
## william
## dbMySQLConnect
## -------------------------------------------------------------------------
cpdef dbMySQLConnect(str dbName):
    """连接 mySQL 数据库"""
    try:
        conn = MySQLdb.connect(db          = dbName,
                               host        = globalSetting().vtSetting["mysqlHost"],
                               port        = globalSetting().vtSetting["mysqlPort"],
                               user        = globalSetting().vtSetting["mysqlUser"],
                               passwd      = globalSetting().vtSetting["mysqlPassword"],
                               use_unicode = True,
                               charset     = "utf8")
        return conn
    except (MySQLdb.Error, MySQLdb.Warning, TypeError) as e:
        print e
## =============================================================================

## =============================================================================
## william
## 从 MySQL 数据库查询数据
## -----------------------------------------------------------------------------
cpdef dbMySQLQuery(str dbName, query):
    """ 从 MySQL 中读取数据 """
    try:
        conn = MySQLdb.connect(db          = dbName,
                               host        = globalSetting().vtSetting["mysqlHost"],
                               port        = globalSetting().vtSetting["mysqlPort"],
                               user        = globalSetting().vtSetting["mysqlUser"],
                               passwd      = globalSetting().vtSetting["mysqlPassword"],
                               use_unicode = True,
                               charset     = "utf8")
        mysqlData = pd.read_sql(str(query), conn)
        return mysqlData
    except (MySQLdb.Error, MySQLdb.Warning, TypeError) as e:
        print e
    # finally:
    #     conn.close()
## =============================================================================

## =============================================================================
## william
## 从 MySQL 数据库发送命令
## -----------------------------------------------------------------------------
cpdef dbMySQLSend(str dbName, query):
    """ 从 MySQL 中读取数据 """
    try:
        # conn = dbMySQLConnect(dbName)
        conn = MySQLdb.connect(db          = dbName,
                               host        = globalSetting().vtSetting["mysqlHost"],
                               port        = globalSetting().vtSetting["mysqlPort"],
                               user        = globalSetting().vtSetting["mysqlUser"],
                               passwd      = globalSetting().vtSetting["mysqlPassword"],
                               use_unicode = True,
                               charset     = "utf8")
        cursor = conn.cursor()
        cursor.execute(query)
        conn.commit()
    except (MySQLdb.Error, MySQLdb.Warning, TypeError) as e:
        print e
    # finally:
    #     conn.close()
## =============================================================================


## =============================================================================
## william
## 实现 MySQL 数据在本地数据库与远程服务器数据库的同步
## -----------------------------------------------------------------------------
cpdef dbMySQLSync(fromHost, toHost, str fromDB, str toDB, tableName = '', condition = ''):
    """同步 MySQL 数据"""
    ## ------------------------------------------------------
    ## condition 格式如下
    ## "--where='TradingDay = {}'".format(stratOI.tradingDay)
    ## ------------------------------------------------------
    cmd = '''mysqldump -h '{fromHost}' -ufl -pabc@123 --opt --compress {fromDB} {tableName} {condition} | mysql -h '{toHost}' -ufl -pabc@123 {toDB}'''.format(
        fromHost = fromHost,
        toHost = toHost,
        fromDB = fromDB, 
        toDB = toDB,
        tableName = tableName,
        condition = condition)
    try:
        ## 不显示 shell 内容
        subprocess.call(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except:
        None
## =============================================================================


## =============================================================================
## william
## 从 MySQL 数据库查询数据
## -----------------------------------------------------------------------------
cpdef fetchMySQL(str db, query):
    ## 用sqlalchemy构建数据库链接 engine
    ## 记得使用 ?charset=utf8 解决中文乱码的问题
    try:
        mysqlInfo = 'mysql+pymysql://{}:{}@{}:{}/{}?charset=utf8'.format(
                        globalSetting().vtSetting["mysqlUser"],
                        globalSetting().vtSetting["mysqlPassword"],
                        globalSetting().vtSetting["mysqlHost"],
                        globalSetting().vtSetting["mysqlPort"],
                        db)
        engine = create_engine(mysqlInfo)
        df = pd.read_sql(query, con = engine)
        return df
    except:
        print u"读取 MySQL 数据库失败"
        return None


## =============================================================================
## william
## 写入 MySQL
## -----------------------------------------------------------------------------
cpdef saveMySQL(df, str db, str tbl, str over, str sourceID = ''):
    ## 用sqlalchemy构建数据库链接 engine
    ## 记得使用 ?charset=utf8 解决中文乱码的问题
    try:
        mysqlInfo = 'mysql+pymysql://{}:{}@{}:{}/{}?charset=utf8'.format(
                        globalSetting().vtSetting["mysqlUser"],
                        globalSetting().vtSetting["mysqlPassword"],
                        globalSetting().vtSetting["mysqlHost"],
                        globalSetting().vtSetting["mysqlPort"],
                        db)
        engine = create_engine(mysqlInfo)
        df.to_sql(name      = tbl,
                  con       = engine,
                  if_exists = over,
                  index     = False)
    except:
        print u"vtFunction.saveMySQL 写入 MySQL 数据库失败 --> " + sourceID


## =============================================================================
ChinaFuturesCalendar = dbMySQLQuery('dev', 
    """select * from ChinaFuturesCalendar where days >= 20180101;""")
ChinaFuturesCalendar.days = ChinaFuturesCalendar.days.apply(str)
ChinaFuturesCalendar.nights = ChinaFuturesCalendar.nights.apply(str)
for i in xrange(len(ChinaFuturesCalendar)):
    ChinaFuturesCalendar.loc[i, 'days'] = ChinaFuturesCalendar.loc[i, 'days'].replace('-','')
    ChinaFuturesCalendar.loc[i, 'nights'] = ChinaFuturesCalendar.loc[i, 'nights'].replace('-','')

ChinaStocksCalendar = dbMySQLQuery('dev', 
    """select * from ChinaStocksCalendar where days >= 20180101;""")
ChinaStocksCalendar.days = ChinaStocksCalendar.days.apply(str)
for i in xrange(len(ChinaStocksCalendar)):
    ChinaStocksCalendar.loc[i, 'days'] = ChinaStocksCalendar.loc[i, 'days'].replace('-','')

## -----------------------------------------------------------------------------
cpdef str tradingDay():
    if 8 <= datetime.now().hour < 17:
        tempRes = datetime.now().strftime("%Y%m%d")
    else:
        temp = ChinaFuturesCalendar[ChinaFuturesCalendar['nights'] <=
                datetime.now().strftime("%Y%m%d")]['days']
        tempRes = temp.tail(1).values[0]
    return tempRes
## -----------------------------------------------------------------------------
cpdef tradingDate():
    return datetime.strptime(tradingDay(),'%Y%m%d').date()
## -----------------------------------------------------------------------------
cpdef str lastTradingDay():
    return ChinaFuturesCalendar.loc[ChinaFuturesCalendar.days <
                                    tradingDay(), 'days'].max()
## -----------------------------------------------------------------------------
cpdef lastTradingDate():
    return datetime.strptime(lastTradingDay(),'%Y%m%d').date()
## =============================================================================



## =========================================================================
## 保存合约信息
cpdef saveContractInfo():
    cdef int i
    try:
        dataFileOld = os.path.join(globalSetting().vtSetting['DATA_PATH'],
                                   globalSetting.accountID,
                                   'ContractInfo',
                                   tradingDay() + '.csv')
        dataFileNew = os.path.normpath(os.path.join(
                                   globalSetting().vtSetting['ROOT_PATH'],
                                   './temp/contract.csv'))
        if os.path.exists(dataFileOld):
            dataOld = pd.read_csv(dataFileOld)
            dataNew = pd.read_csv(dataFileNew)
            for i in xrange(dataOld.shape[0]):
                if dataNew.at[i,'symbol'] not in dataOld.symbol.values:
                    dataOld = dataOld.append(dataNew.loc[i], ignore_index = True)
            dataOld.to_csv(dataFileOld, index = False)
        else:
            copyfile(dataFileNew,dataFileOld)
    except:
        None
## =========================================================================

############################################################################
## 验证 IP 有效性
############################################################################
cpdef vetifyIP(ip, int count = 1, timeout = 1):
    """验证 Ip 有效性"""
    cmd = '/bin/ping -c%d -w%d %s' %(count, timeout, ip)

    rsp = subprocess.Popen(cmd, 
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    shell=True
                    )

    result = rsp.stdout.read()

    ## 结果为空
    if not result:
        return None

    regex = re.findall('100% packet loss', result)

    if len(regex) != 0:
        ## 存在丢包
        return None
    else:
        ## 没有丢包
        return True

############################################################################
## 发送邮件通知
############################################################################
cpdef sendMail(accountName, content):
    """发送邮件通知给：汉云交易员"""
    cdef:
        list receiversMain = ['fl@hicloud-investment.com']
        list receiversOthers = ['lhg@hicloud-investment.com']
        char* sender = "trader@hicloud.com"

    message = MIMEText(content.decode('string-escape').decode("utf-8"), 'plain', 'utf-8')
    ## 显示:发件人
    message['From'] = Header(sender, 'utf-8')
    ## 显示:收件人
    message['To']   =  Header('汉云交易员', 'utf-8')
    ## 主题
    subject = tradingDay() + '：' + accountName + u'~~ 启禀大王，你家后院着火了 ~~'
    message['Subject'] = Header(subject, 'utf-8')

    ## ---------------------------------------------------------------------
    try:
        smtpObj = smtplib.SMTP('localhost')
        # smtpObj.sendmail(sender, receiversMain + receiversOthers, message.as_string())
        smtpObj.sendmail(sender, receiversMain, message.as_string())
        print(u'预警邮件发送成功')
    except smtplib.SMTPException:
        print(u'预警邮件发送失败')
    ## ---------------------------------------------------------------------

cpdef getHostIP():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
        s.close()
    except:
        return None

