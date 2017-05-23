# encoding: UTF-8
################################################################################
## william
## vtFunction 模块定义了顶层使用的一些函数
## ///////////////////////////////////
## Usage: vtFunction.func()
## ///////////////////////////////////
##
## 1. vtFunction.loadMySQLSetting()
##    从 /main/VT_setting.json 获取 MySQL 的配置文件
## 2. vtFunction.tradingDay()
##    获取当前时间对应的交易所交易日历
## 3. 
################################################################################

## =============================================================================
import os
import decimal
import json
import shelve
from datetime import datetime

import numpy as np
import pandas as pd
pd.set_option('display.width', 200)
pd.set_option('display.max_rows', 30)
from pandas import DataFrame,Series

from datetime import datetime

MAX_NUMBER = 10000000000000
MAX_DECIMAL = 4
## =============================================================================


#-------------------------------------------------------------------------------
def safeUnicode(value):
    """检查接口数据潜在的错误，保证转化为的字符串正确"""
    # 检查是数字接近0时会出现的浮点数上限
    if type(value) is int or type(value) is float:
        if value > MAX_NUMBER:
            value = 0
    
    # 检查防止小数点位过多
    if type(value) is float:
        d = decimal.Decimal(str(value))
        if abs(d.as_tuple().exponent) > MAX_DECIMAL:
            value = round(value, ndigits=MAX_DECIMAL)
    
    return unicode(value)


#-------------------------------------------------------------------------------
def loadMongoSetting():
    """载入MongoDB数据库的配置"""
    fileName = 'VT_setting.json'
    ############################################################################
    ## william
    path     = os.path.abspath(os.path.dirname(__file__))
    fileName = os.path.join(path, fileName)
    ############################################################################
    
    try:
        f       = file(fileName)
        setting = json.load(f)
        host    = setting['mongoHost']
        port    = setting['mongoPort']
        logging = setting['mongoLogging']
    except:
        host    = 'localhost'
        port    = 27017
        logging = False
        
    return host, port, logging


################################################################################
## william
## MySQL setting
################################################################################
# path = '/home/william/Documents/vnpy/vnpy-1.6.1/vn.trader'
# fileName = os.path.join(path, "VT_setting.json")
# ------------------------------------------------------------------------------
def loadMySQLSetting():
    """载入MongoDB数据库的配置"""
    fileName = 'VT_setting.json'
    ############################################################################
    ## william
    path     = os.path.abspath(os.path.dirname(__file__))
    fileName = os.path.join(path, fileName)
    ############################################################################ 
    
    try:
        f = file(fileName)
        setting = json.load(f)
        host    = setting['mysqlHost']
        port    = setting['mysqlPort']
        user    = setting['mysqlUser']
        passwd  = setting['mysqlPassword']
    except:
        host    = '192.168.1.106'
        port    = 3306
        user    = 'fl'
        passwd  = 'abc@123'
        
    return host, port, user, passwd


#-------------------------------------------------------------------------------
def todayDate():
    """获取当前本机电脑时间的日期"""
    return datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)    


################################################################################
## william
## 当前日期所对应的交易所的交易日历: tradingDay
################################################################################
def tradingDay():
    """ 交易日 """
    fileName = 'ChinaFuturesCalendar.csv'
    ############################################################################
    ## william
    path     = os.path.abspath(os.path.dirname(__file__))
    ChinaFuturesCalendar = os.path.join(path, fileName)
    ############################################################################ 
    ChinaFuturesCalendar = pd.read_csv(ChinaFuturesCalendar)
    ChinaFuturesCalendar = ChinaFuturesCalendar[ChinaFuturesCalendar['days'].fillna(0) >= 20170101].reset_index(drop = True)    
    # print ChinaFuturesCalendar.dtypes
    ChinaFuturesCalendar.days = ChinaFuturesCalendar.days.apply(str)
    ChinaFuturesCalendar.nights = ChinaFuturesCalendar.nights.apply(str)

    for i in range(len(ChinaFuturesCalendar)):
        ChinaFuturesCalendar.loc[i, 'nights'] = ChinaFuturesCalendar.loc[i, 'nights'].replace('.0','')

    if 8 <= datetime.now().hour < 20:
        tempRes = datetime.now().strftime("%Y%m%d")
    else:
        temp = ChinaFuturesCalendar[ChinaFuturesCalendar['nights'] == datetime.now().strftime("%Y%m%d")]['days']
        tempRes = str(temp.iloc[0])

    return tempRes


################################################################################
## william
## 保存 CTP md 的数据为 csv
## Ref: http://www.vnpie.com/forum.php?mod=viewthread&tid=964&highlight=%E6%95%B0%E6%8D%AE
################################################################################
'''
'''
def refreshDatarecodeSymbol():
    """ 保存合约信息到 dataRecorder/DR_setting.json """
    contractFileName = 'ContractData.vt'

    contractDict = {}
    jfile = os.path.join('/home/william/Documents/vnpy/vnpy-1.6.1/vn.trader/dataRecorder/','DR_setting.json')
    jf    = open(jfile,'w')

    drSetting            = {}
    drSetting['tick']    = []
    drSetting['working'] = True

    f = shelve.open(os.path.join('/home/william/Documents/vnpy/vnpy-1.6.1/vn.trader/',contractFileName))
    if 'data' in f:
        d = f['data']
        print "全部期货与期权合约数量为:==> ",len(d)
        for key, value in d.items():
            contractDict[key] = value
            # print value.symbol, value.name, value.productClass, value.exchange, value.size, value.priceTick
            drSetting['tick'].append([value.symbol,value.exchange])
    f.close()

    ## print drSetting
    json.dump(drSetting,jf)
    jf.close()


################################################################################
## wiliam
## getContractInfo()
## 获取当天的所有合约信息,并保存为 csv 文件
################################################################################

def getContractInfo():
    """ 获取合约信息 """
    contractFileName='ContractData.vt'

    f = shelve.open(os.path.join('/home/william/Documents/vnpy/vnpy-1.6.1/vn.trader/',contractFileName))
    #print f 

    """
    InstrumentID    :合约代码
    InstrumentName  :合约名称
    ProductClass    :产品类型:期货,期权
    ExchangeID      :交易所代码
    VolumeMultiple  :合约乘数
    priceTick       :最小变动价格
    """ 

    contractInfoHeader = ["InstrumentID", "InstrumentName", "ProductClass",\
                          "ExchangeID", "VolumeMultiple", "PriceTick"]    
    contractInfoData = []   

    for key, value in f['data'].items():
        data = [value.symbol, value.name, value.productClass, value.exchange,\
                value.size, value.priceTick]
        #print data
        contractInfoData.append(data)   
    f.close()
    #print contractInfoData
    contractInfo = DataFrame(contractInfoData, columns = contractInfoHeader)
    return contractInfo


if __name__ == '__main__':
    ## 保存合约信息到 DR_setting.json
    refreshDatarecodeSymbol()

    ## 获取合约信息
    getContractInfo()