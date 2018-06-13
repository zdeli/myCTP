# encoding: UTF-8
## =============================================================================
# 重载sys模块，设置默认字符串编码方式为utf8
try:
    reload         # Python 2
except NameError:  # Python 3
    from importlib import reload
import sys
reload(sys)
sys.setdefaultencoding('utf8')
## =============================================================================


## =============================================================================
ROOT_PATH = "/home/william/Documents/myCTP/vnpy-master-1.8.1"

import os,subprocess
from time import sleep
from datetime import datetime,time

os.putenv('DISPLAY', ':0.0')
os.chdir(ROOT_PATH)
sys.path.append(ROOT_PATH)
## =============================================================================


## =============================================================================
## vn.trader模块
from vnpy.event import EventEngine
from vnpy.trader.vtEngine import MainEngine, LogEngine
from vnpy.trader.uiQt import createQApp
from vnpy.trader.uiMainWindow import MainWindow
from vnpy.trader import vtFunction 

## 加载底层接口
from vnpy.trader.gateway import (ctpGateway, xtpGateway)

## 加载上层应用
from vnpy.trader.app import (riskManager, ctaStrategy)
## =============================================================================


## =============================================================================
# def main():
"""主程序入口"""
# 创建Qt应用对象

qApp = createQApp()

## 创建日志引擎
le = LogEngine()
le.setLogLevel(le.LEVEL_INFO)

## 创建事件引擎
ee = EventEngine()
## 创建主引擎
me = MainEngine(ee)

## 添加交易接口
me.addGateway(ctpGateway)
me.addGateway(xtpGateway)

# 添加上层应用
me.addApp(riskManager)
me.addApp(ctaStrategy)

## ----------------------
le.info('-'*49)
le.info(u'准备启动交易模块')
le.info('-'*49)
le.info(u'主引擎创建成功')
## ----------------------

## ----------------------
## 创建主窗口
mw = MainWindow(me, ee)
mw.showMaximized()
## ----------------------










## -----------------------------------------------------------------------------
## 在主线程中启动Qt事件循环
# sys.exit(qApp.exec_())
## =============================================================================
