param([string]$NativeHelperPath)
$ErrorActionPreference = 'Stop'
Add-Type -Path $NativeHelperPath
# CI's parent has redirected stdout. Open the attached fixture's actual console
# OUTPUT explicitly, rather than inheriting that runner pipe in the child.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DracoTransportFixture {
    [StructLayout(LayoutKind.Sequential)] public struct XY { public short x,y; }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public short left,top,right,bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Info { public XY size,cursor; public ushort attributes; public Rect window; public XY maximum; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFileW(string name,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll")] static extern bool SetStdHandle(int kind,IntPtr handle);
    [DllImport("kernel32.dll")] static extern bool GetConsoleScreenBufferInfo(IntPtr handle,out Info info);
    [DllImport("kernel32.dll")] static extern bool SetConsoleCursorPosition(IntPtr handle,XY position);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] static extern bool WriteConsoleW(IntPtr handle,string text,uint length,out uint written,IntPtr reserved);
    static IntPtr output=IntPtr.Zero;
    public static void Open() {
        output=CreateFileW("CONOUT$",0xC0000000,3,IntPtr.Zero,3,0,IntPtr.Zero);
        if(output==new IntPtr(-1) || !SetStdHandle(-11,output)) throw new Exception("Fixture console output unavailable");
        if(!SetConsoleCursorPosition(output,new XY())) throw new Exception("Fixture cursor unavailable");
        Write("Z");
    }
    public static int Cursor() {Info info; if(!GetConsoleScreenBufferInfo(output,out info)) throw new Exception("Fixture console info unavailable"); return info.cursor.y*1000+info.cursor.x;}
    public static void Write(string text) {uint written; if(!WriteConsoleW(output,text,(uint)text.Length,out written,IntPtr.Zero) || written!=text.Length) throw new Exception("Fixture output failed");}
}
'@
[DracoTransportFixture]::Open()
$Cursor = [DracoTransportFixture]::Cursor()
[Draco.InputPulse]::Start()
[Draco.InputPulse]::Reset()
[Draco.InputPulse]::Click()
[Draco.InputPulse]::Click()
Start-Sleep -Milliseconds 650
if ([Draco.InputPulse]::Emitted -ne 2 -or [Draco.InputPulse]::Transport -ne 1 -or [Draco.InputPulse]::OutputError -ne 0) { exit 2 }
if ([DracoTransportFixture]::Cursor() -ne $Cursor) { exit 3 }
[Draco.InputPulse]::Fire()
Start-Sleep -Milliseconds 1100
if ([Draco.InputPulse]::Fires -ne 1 -or [Draco.InputPulse]::OutputError -ne 0) { exit 4 }
if ([DracoTransportFixture]::Cursor() -ne $Cursor) { exit 5 }
[Draco.InputPulse]::Stop()
[DracoTransportFixture]::Write('DRACO-WIRE-PASS')

