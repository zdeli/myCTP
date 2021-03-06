#!/bin/bash
## 清理原来的 .c .so 文件

## =============================================================================
# rm -f ./*.c
rm -f ./*.so

rm -f ./app/ctaStrategy/*.so

rm -f ./app/ctaStrategy/strategy/*.so

rm -f ./app/dataRecorder/*.so

rm -f ./app/riskManager/*.so

rm -f ./gateway/ctpGateway/*.so

rm -f ./gateway/ctpGatewayRecorder/*.so
## =============================================================================


## =============================================================================
python setup.py build_ext --inplace
## =============================================================================


## =============================================================================
rm -rf ./build
rm -rf ./app/**/build
rm -rf ./gateway/**/build
rm -rf ../event/**/build
## =============================================================================
