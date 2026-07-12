# CommonLib host tests

`TcNumeric` と `TcUnits` の TwinCAT 非依存ロジックを Windows host 上で検証する。

```powershell
msbuild CommonLib/tests/CommonLibTests.vcxproj /p:Configuration=Release /p:Platform=x64
.tmp/commonlib-tests/Release/CommonLibTests.exe
```
