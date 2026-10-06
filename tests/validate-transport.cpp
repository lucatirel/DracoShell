// Reads only output from a disposable synthetic PowerShell/ConPTY fixture.
// Production InputPulse never opens or reads any input/console content.
#include <windows.h>
#include <string>
#include <vector>
#include <thread>
#include <iostream>
#include <stdexcept>
void ok(BOOL success) { if(!success) throw std::runtime_error("Win32 error "+std::to_string(GetLastError())); }
int wmain(int argc,wchar_t** argv) {
    HANDLE inR=nullptr,inW=nullptr,outR=nullptr,outW=nullptr;
    HPCON console=nullptr; PROCESS_INFORMATION process{};
    LPPROC_THREAD_ATTRIBUTE_LIST attributes=nullptr;
    std::thread reader; std::string trace;
    try {
        if(argc!=3) throw std::runtime_error("Expected InputPulse.cs and fixture script paths");
        wchar_t full[MAX_PATH]; ok(GetFullPathNameW(argv[1],MAX_PATH,full,nullptr));
        ok(CreatePipe(&inR,&inW,nullptr,0)); ok(CreatePipe(&outR,&outW,nullptr,0));
        HRESULT hr=CreatePseudoConsole(COORD{80,25},inR,outW,0,&console);
        if(FAILED(hr)) throw std::runtime_error("CreatePseudoConsole failed");
        CloseHandle(inR); inR=nullptr; CloseHandle(outW); outW=nullptr;
        // Read the fixture's OUTPUT pipe only. No input is submitted or read.
        reader=std::thread([&] {
            char bytes[4096]; DWORD count;
            while(ReadFile(outR,bytes,sizeof(bytes),&count,nullptr) && count) trace.append(bytes,count);
        });
        SIZE_T size=0; InitializeProcThreadAttributeList(nullptr,1,0,&size);
        std::vector<unsigned char> storage(size); attributes=(LPPROC_THREAD_ATTRIBUTE_LIST)storage.data();
        ok(InitializeProcThreadAttributeList(attributes,1,0,&size));
        ok(UpdateProcThreadAttribute(attributes,0,PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,console,sizeof(HPCON),nullptr,nullptr));
        STARTUPINFOEXW startup{}; startup.StartupInfo.cb=sizeof(startup); startup.lpAttributeList=attributes;
        // Child compiles the real helper, writes a known Z, and performs two
        // anonymous clicks. It never calls the observer seam used by unit tests.
        std::wstring command=L"powershell.exe -NoLogo -NoProfile -NonInteractive -File \"";
        command+=argv[2]; command+=L"\" -NativeHelperPath \"";
        command+=full; command+=L"\"";
        ok(CreateProcessW(nullptr,&command[0],nullptr,nullptr,FALSE,EXTENDED_STARTUPINFO_PRESENT,nullptr,nullptr,&startup.StartupInfo,&process));
        if(WaitForSingleObject(process.hProcess,30000)!=WAIT_OBJECT_0) {
            TerminateProcess(process.hProcess,1); throw std::runtime_error("Fixture timed out");
        }
        DWORD exit=0; ok(GetExitCodeProcess(process.hProcess,&exit));
        ClosePseudoConsole(console); console=nullptr; reader.join();
        CloseHandle(outR); outR=nullptr; CloseHandle(inW); inW=nullptr;
        DeleteProcThreadAttributeList(attributes); attributes=nullptr;
        CloseHandle(process.hThread); process.hThread=nullptr; CloseHandle(process.hProcess); process.hProcess=nullptr;
        if(exit!=0 || trace.find("DRACO-WIRE-PASS")==std::string::npos)
            throw std::runtime_error("Native click/output fixture failed, exit="+std::to_string(exit));
        // Older ConPTY serializes a cell repaint as RGB SGR; newer builds can
        // forward DECCARA itself. Both must contain the fixed RGB control value.
        if(trace.find("5;56;22")==std::string::npos && trace.find("5:56:22")==std::string::npos)
            throw std::runtime_error("Fixed control RGB did not reach ConPTY output");
        if(trace.find("5;8;8")==std::string::npos && trace.find("5:8:8")==std::string::npos)
            throw std::runtime_error("Enter fire RGB did not reach ConPTY output");
        std::cout << "Native PowerShell 5.1 WriteConsoleW -> ConPTY: two pulses, RGB control delivered, cursor preserved: PASS\n";
        return 0;
    } catch(const std::exception& e) {
        if(process.hProcess) {TerminateProcess(process.hProcess,1); CloseHandle(process.hProcess);}
        if(process.hThread) CloseHandle(process.hThread);
        if(console) ClosePseudoConsole(console);
        if(inR) CloseHandle(inR); if(outW) CloseHandle(outW); if(inW) CloseHandle(inW);
        if(reader.joinable()) reader.join();
        if(outR) CloseHandle(outR);
        // Attribute backing storage has unwound; do not dereference it here.
        std::cerr << e.what() << '\n'; return 1;
    }
}

