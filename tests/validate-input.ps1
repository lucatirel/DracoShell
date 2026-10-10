$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Source = [IO.File]::ReadAllText((Join-Path $RepoRoot 'input\InputPulse.cs'))
Add-Type -TypeDefinition ($Source + @'
public static class DracoInputValidator {
    public static void MuteOutput() { Draco.InputPulse.OutputObserver = delegate(bool on) { }; }
    public static void UnmuteOutput() { Draco.InputPulse.OutputObserver = null; }
    public static void Validate() {
        if (typeof(Draco.InputPulse).GetMethod("Click").GetParameters().Length != 0 ||
            typeof(Draco.InputPulse).GetMethod("Fire").GetParameters().Length != 0 ||
            typeof(Draco.InputPulse).GetMethod("Flight").GetParameters().Length != 0)
            throw new System.Exception("Effects API accepts input data");
        if (Draco.InputPulse.OnSequence != "\u001b[1;1;1;1;48;2;5;56;22$r" ||
            Draco.InputPulse.OffSequence != "\u001b[1;1;1;1;49$r")
            throw new System.Exception("Control cell sequence modifies more than one background attribute");
        // Lock the native surface to output-only calls, not just zero-arg API names.
        foreach(var method in typeof(Draco.InputPulse).GetMethods(
            System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public)) {
            foreach(System.Runtime.InteropServices.DllImportAttribute import in method.GetCustomAttributes(
                typeof(System.Runtime.InteropServices.DllImportAttribute), false)) {
                if(import.Value != "kernel32.dll" ||
                    (import.EntryPoint != "GetStdHandle" && import.EntryPoint != "GetConsoleMode" &&
                     import.EntryPoint != "SetConsoleMode" && import.EntryPoint != "WriteConsoleW"))
                    throw new System.Exception("Pulse component introduced an unexpected native API");
            }
        }
        var sequences = new System.Collections.Generic.List<string>();
        Draco.InputPulse.SequenceObserver = delegate(string value) { sequences.Add(value); };
        try {
            Draco.InputPulse.Start(); Draco.InputPulse.Reset(); sequences.Clear();
            Draco.InputPulse.ShowDiagnostic(false);
            Draco.InputPulse.Reset();
            Draco.InputPulse.ShowDiagnostic(true);
            Draco.InputPulse.Stop();
            if (sequences.Count != 4 || sequences[0] != Draco.InputPulse.OnSequence ||
                sequences[1] != Draco.InputPulse.OffSequence ||
                sequences[2] != Draco.InputPulse.DiagnosticSequence ||
                sequences[3] != Draco.InputPulse.OffSequence)
                throw new System.Exception("Held diagnostics did not restore the background attribute");
        } finally { Draco.InputPulse.Stop(); Draco.InputPulse.SequenceObserver=null; }
        var gate = new Draco.PulseGate();
        if (gate.Advance(0) != -1) throw new System.Exception("Idle effect activated");
        gate.Press(); gate.Press(); // Equivalent to two anonymous insertions: l, s.
        if (gate.Advance(0) != 1 || gate.Advance(139) != -1 || gate.Advance(140) != 0 ||
            gate.Advance(209) != -1 || gate.Advance(210) != 1 || gate.Advance(350) != 0 || gate.Pending)
            throw new System.Exception("Two quick presses did not create two separate flashes");
        var flood = new Draco.PulseGate();
        for (int i=0; i<10000; i++) flood.Press();
        int floodPulses=0;
        for (int now=0; now<3000; now++) if (flood.Advance(now)==1) floodPulses++;
        if (floodPulses != Draco.PulseGate.QueueLimit || flood.Pending)
            throw new System.Exception("Flood queue unbounded or failed to drain");
        var output = new System.Collections.Generic.List<bool>();
        Draco.InputPulse.OutputObserver = delegate(bool on) { output.Add(on); };
        try {
            Draco.InputPulse.Start();
            Draco.InputPulse.Start();
            Draco.InputPulse.Reset(); output.Clear();
            Draco.InputPulse.Click(); Draco.InputPulse.Click();
            System.Threading.Thread.Sleep(650);
            Draco.InputPulse.Stop();
            int on=0; foreach (bool value in output) if(value) on++;
            if (on != 2 || Draco.InputPulse.Received != 2 || Draco.InputPulse.Emitted != 2 || output[output.Count-1])
                throw new System.Exception("Native timer failed to emit exactly two quick press pulses");
            output.Clear();
            Draco.InputPulse.Start(); Draco.InputPulse.Reset();
            var watch=System.Diagnostics.Stopwatch.StartNew();
            for(int i=0; i<10000; i++) Draco.InputPulse.Click();
            watch.Stop();
            if(watch.ElapsedMilliseconds>1000 || Draco.InputPulse.Received!=10000)
                throw new System.Exception("Anonymous press counter slow or incorrect");
            Draco.InputPulse.Stop();
            System.Console.WriteLine("Anonymous two-press/two-flash timer and bounded flood queue: PASS");
            System.Console.WriteLine("Anonymous 10000-click path: " + watch.ElapsedMilliseconds + " ms: PASS");
        } finally { Draco.InputPulse.Stop(); Draco.InputPulse.OutputObserver=null; }
        // A stalled console write must not delay either anonymous editor call.
        var entered = new System.Threading.ManualResetEvent(false);
        var release = new System.Threading.ManualResetEvent(false);
        System.Threading.Thread caller = null;
        long stalledCallMs = -1;
        try {
            Draco.InputPulse.Start(); Draco.InputPulse.Reset();
            Draco.InputPulse.OutputObserver = delegate(bool on) {
                if(on) { entered.Set(); if(!release.WaitOne(3000)) throw new System.Exception("Stall fixture timed out"); }
            };
            Draco.InputPulse.Click();
            if(!entered.WaitOne(2000)) throw new System.Exception("No background write to stall");
            caller = new System.Threading.Thread(delegate() {
                var watch = System.Diagnostics.Stopwatch.StartNew();
                Draco.InputPulse.Click(); Draco.InputPulse.Fire(); Draco.InputPulse.Flight();
                watch.Stop(); stalledCallMs = watch.ElapsedMilliseconds;
            });
            caller.Start();
            if(!caller.Join(250)) throw new System.Exception("Editor waited for stalled graphics output");
            if(stalledCallMs > 100) throw new System.Exception("Anonymous editor calls too slow during output stall");
        } finally {
            release.Set(); if(caller != null) caller.Join(2000);
            Draco.InputPulse.Stop(); Draco.InputPulse.OutputObserver=null;
            entered.Dispose(); release.Dispose();
        }
        System.Console.WriteLine("Click/Fire/Flight while graphics output is blocked: " + stalledCallMs + " ms: PASS");
        if (Draco.InputPulse.FlameStage(-1)!=-1 || Draco.InputPulse.FlameStage(0)!=0 ||
            Draco.InputPulse.FlameStage(899)!=19 || Draco.InputPulse.FlameStage(900)!=-1)
            throw new System.Exception("Fire duration unbounded");
        var fireWire = new System.Collections.Generic.List<string>();
        Draco.InputPulse.SequenceObserver = delegate(string value) { fireWire.Add(value); };
        try {
            Draco.InputPulse.Start(); Draco.InputPulse.Reset(); fireWire.Clear();
            Draco.InputPulse.Fire(); Draco.InputPulse.Click();
            System.Threading.Thread.Sleep(1100);
            if (Draco.InputPulse.Fires!=1 || Draco.InputPulse.Received!=1 || Draco.InputPulse.Emitted!=1 ||
                !fireWire[0].EndsWith(";80$r") ||
                !fireWire.Exists(delegate(string s) {return s.Contains("5;56;8");}) ||
                fireWire[fireWire.Count-1]!=Draco.InputPulse.OffSequence || fireWire.Count>30)
                throw new System.Exception("Independent fire/typing signal or bounded fire output failed");
            Draco.InputPulse.Reset(); fireWire.Clear();
            for(int i=0;i<200;i++) Draco.InputPulse.Fire();
            System.Threading.Thread.Sleep(1100);
            if(Draco.InputPulse.Fires!=200 || fireWire[fireWire.Count-1]!=Draco.InputPulse.OffSequence)
                throw new System.Exception("Held Enter created a delayed fire queue");
        } finally {Draco.InputPulse.Stop(); Draco.InputPulse.SequenceObserver=null;}
        System.Console.WriteLine("Anonymous Enter fire, concurrent green signal, expiry and no fire backlog: PASS");
        if(Draco.InputPulse.FlightStage(-1)!=-1 || Draco.InputPulse.FlightStage(0)!=0 ||
           Draco.InputPulse.FlightStage(5499)!=109 || Draco.InputPulse.FlightStage(5500)!=-1)
            throw new System.Exception("Flight duration is not bounded");
        var flightWire=new System.Collections.Generic.List<string>();
        Draco.InputPulse.SequenceObserver=delegate(string value){flightWire.Add(value);};
        try {
            Draco.InputPulse.Start(); Draco.InputPulse.Reset(); flightWire.Clear();
            Draco.InputPulse.Flight(); Draco.InputPulse.Fire(); Draco.InputPulse.Click();
            System.Threading.Thread.Sleep(5800);
            if(!flightWire.Exists(delegate(string value){return value.Contains(";48;2;128;");}) ||
               !flightWire.Exists(delegate(string value){return value.Contains(";56;8");}) ||
               flightWire[flightWire.Count-1]!=Draco.InputPulse.OffSequence || flightWire.Count>145)
                throw new System.Exception("Flight/typing/fire channels or flight expiry failed");
            flightWire.Clear();
            for(int i=0;i<200;i++) Draco.InputPulse.Flight();
            System.Threading.Thread.Sleep(120);
            Draco.InputPulse.Reset();
            int stoppedCount=flightWire.Count;
            System.Threading.Thread.Sleep(160);
            if(flightWire.Count!=stoppedCount || flightWire[flightWire.Count-1]!=Draco.InputPulse.OffSequence)
                throw new System.Exception("Reset did not cancel flight flood immediately");
        } finally { Draco.InputPulse.Stop(); Draco.InputPulse.SequenceObserver=null; }
        System.Console.WriteLine("Bounded flight, independent channels, expiry and immediate cancel: PASS");

    }
}
'@)
[DracoInputValidator]::Validate()

Import-Module PSReadLine
$EnterBefore = @(Get-PSReadLineKeyHandler -Bound | Where-Object Key -eq 'Enter') | ConvertTo-Json
Set-PSReadLineKeyHandler -Key x -BriefDescription DracoCustomFixture -ScriptBlock { }
. (Join-Path $RepoRoot 'profile\draco-input.ps1')
Enable-DracoTypingEffects
$Handlers = @(Get-PSReadLineKeyHandler -Bound)
if (@($Handlers | Where-Object Function -eq 'DracoSelfInsert').Count -lt 26) { throw 'Typing adapter did not bind character insertion' }
if (@($Handlers | Where-Object { $_.Key -eq 'x' -and $_.Function -eq 'DracoCustomFixture' }).Count -ne 1) { throw 'Custom key binding overwritten' }
$EnterAfter = @($Handlers | Where-Object Key -eq 'Enter') | ConvertTo-Json
if (@($Handlers | Where-Object { $_.Key -eq 'Enter' -and $_.Function -eq 'DracoSubmit' }).Count -ne 1) { throw 'Stock Enter was not wrapped' }
$BeforeCount = @($Handlers | Where-Object Function -eq 'DracoSelfInsert').Count
Enable-DracoTypingEffects
if (@(Get-PSReadLineKeyHandler -Bound | Where-Object Function -eq 'DracoSelfInsert').Count -ne $BeforeCount) { throw 'Duplicate typing bindings' }
Disable-DracoTypingEffects
if ([Draco.InputPulse]::Enabled) { throw 'Disable command failed' }
if ($EnterBefore -cne (@(Get-PSReadLineKeyHandler -Bound | Where-Object Key -eq 'Enter') | ConvertTo-Json)) { throw 'Original Enter action was not restored' }
if (@(Get-PSReadLineKeyHandler -Bound | Where-Object Function -eq 'DracoSelfInsert').Count) { throw 'Disable left insertion wrappers installed' }
Enable-DracoTypingEffects
if (@(Get-PSReadLineKeyHandler -Bound | Where-Object Function -eq 'DracoSelfInsert').Count -ne $BeforeCount) { throw 'Re-enable failed' }
Disable-DracoTypingEffects
Set-PSReadLineKeyHandler -Key Enter -BriefDescription DracoCustomEnterFixture -ScriptBlock { }
Enable-DracoTypingEffects
if (@(Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq 'Enter' -and $_.Function -eq 'DracoCustomEnterFixture' }).Count -ne 1) { throw 'Custom Enter overwritten' }
Disable-DracoTypingEffects

# The adapter may only forward opaque editor arguments, never inspect them.
$Adapter = [IO.File]::ReadAllText((Join-Path $RepoRoot 'profile\draco-input.ps1'))
$Code = [regex]::Replace($Adapter, '(?m)^\s*#.*$', '')
if ($Code -match 'KeyChar|GetBufferState|Get-History|Clipboard|ReadKey|ReadLine\(|ToUnicode|Start-Process') {
    throw 'Typing adapter inspects input or starts per-key processes'
}
# Run the public diagnostic as one command: its own status reports two presses,
# so typing a second status command cannot inflate the test counters.
[DracoInputValidator]::MuteOutput()
try {
    $VisualStatus = Test-DracoTypingEffects -Seconds 1
    if ($VisualStatus.Received -ne 2 -or $VisualStatus.Emitted -ne 2 -or $VisualStatus.Protocol -ne 'cell-v4-fire') {
        throw 'Held visual test failed to isolate its two anonymous pulses'
    }
} finally { Disable-DracoTypingEffects; [DracoInputValidator]::UnmuteOutput() }
Write-Host 'Submit adapter restores stock Enter, preserves custom bindings and forwards no text: PASS'

