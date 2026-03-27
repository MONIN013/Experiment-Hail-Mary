$source = @"
using System;
using System.Runtime.InteropServices;

public class MarshalHelper {
    [DllImport("ole32.dll")]
    private static extern int CLSIDFromProgID([MarshalAs(UnmanagedType.LPWStr)] string lpszProgID, out Guid pclsid);

    [DllImport("oleaut32.dll", PreserveSig = false)]
    private static extern void GetActiveObject(ref Guid rclsid, IntPtr pvReserved, [MarshalAs(UnmanagedType.IUnknown)] out object ppunk);

    public static object GetActiveObject(string progId) {
        Guid clsid;
        CLSIDFromProgID(progId, out clsid);
        object obj;
        GetActiveObject(ref clsid, IntPtr.Zero, out obj);
        return obj;
    }
}
"@

# クラスをコンパイルして読み込む
Add-Type -TypeDefinition $source

# 代替メソッドでDTEオブジェクトを取得
$dte = [MarshalHelper]::GetActiveObject("VisualStudio.DTE.16.0")

msbuild "C:\Users\Nogiku\source\repos\ExperimentHailMary\ExperimentHailMary\ExperimentHailMary.sln" /t:Rebuild /p:Configuration=Debug