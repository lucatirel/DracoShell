// Offscreen production-shader regression, including Terminal's alpha-zero BG.
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <vector>
#include <iostream>
#include <stdexcept>
#include <string>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <fstream>
#include <filesystem>
using Microsoft::WRL::ComPtr;
void check(HRESULT hr) { if (FAILED(hr)) throw std::runtime_error("Direct3D/WIC call failed: " + std::to_string(hr)); }
struct Constants { float time, scale, width, height, background[4]; };
struct Pixel { unsigned char r,g,b,a; };
std::vector<Pixel> atlas(const wchar_t* path, UINT& width, UINT& height) {
    ComPtr<IWICImagingFactory> factory;
    check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)));
    ComPtr<IWICBitmapDecoder> decoder;
    check(factory->CreateDecoderFromFilename(path, nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad, &decoder));
    ComPtr<IWICBitmapFrameDecode> frame;
    check(decoder->GetFrame(0, &frame)); check(frame->GetSize(&width, &height));
    ComPtr<IWICFormatConverter> converter; check(factory->CreateFormatConverter(&converter));
    check(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppPRGBA, WICBitmapDitherTypeNone,
        nullptr, 0, WICBitmapPaletteTypeCustom));
    std::vector<Pixel> pixels(width*height);
    check(converter->CopyPixels(nullptr, width*4, (UINT)pixels.size()*4, (BYTE*)pixels.data()));
    return pixels;
}
ComPtr<ID3D11Texture2D> texture(ID3D11Device* device, UINT width, UINT height, const std::vector<Pixel>& pixels) {
    D3D11_TEXTURE2D_DESC d{}; d.Width=width; d.Height=height; d.MipLevels=d.ArraySize=1;
    d.Format=DXGI_FORMAT_R8G8B8A8_UNORM; d.SampleDesc.Count=1; d.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA initial{}; initial.pSysMem=pixels.data(); initial.SysMemPitch=width*4;
    ComPtr<ID3D11Texture2D> t; check(device->CreateTexture2D(&d, &initial, &t)); return t;
}
int wmain(int argc, wchar_t** argv) {
    try {
        if(argc != 3 && argc != 4) throw std::runtime_error("Expected shader and atlas paths, plus optional demo output");
        check(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
        ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> context;
        check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0, nullptr, 0,
            D3D11_SDK_VERSION, &device, nullptr, &context));
        ComPtr<ID3DBlob> code, errors;
        HRESULT hr=D3DCompileFromFile(argv[1], nullptr, nullptr, "main", "ps_4_0", 2048, 0, &code, &errors);
        if(FAILED(hr) && errors) std::cerr << (const char*)errors->GetBufferPointer();
        check(hr); ComPtr<ID3D11PixelShader> ps;
        check(device->CreatePixelShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &ps));
        const char* vsSource="struct V {float4 p:SV_POSITION;float2 u:TEXCOORD0;};"
            "V main(uint i:SV_VertexID){V v;float2 u=float2((i<<1)&2,i&2);"
            "v.p=float4(u.x*2-1,1-u.y*2,0,1);v.u=u;return v;}";
        check(D3DCompile(vsSource, strlen(vsSource), nullptr, nullptr, nullptr, "main", "vs_4_0", 0, 0, &code, &errors));
        ComPtr<ID3D11VertexShader> vs;
        check(device->CreateVertexShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &vs));
        context->VSSetShader(vs.Get(), nullptr, 0); context->PSSetShader(ps.Get(), nullptr, 0);
        context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        D3D11_SAMPLER_DESC sd{}; sd.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP; sd.MaxLOD=D3D11_FLOAT32_MAX;
        ComPtr<ID3D11SamplerState> sampler; check(device->CreateSamplerState(&sd, &sampler));
        ID3D11SamplerState* samplers[]={sampler.Get()}; context->PSSetSamplers(0,1,samplers);
        D3D11_BUFFER_DESC bd{}; bd.ByteWidth=sizeof(Constants); bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        ComPtr<ID3D11Buffer> constants; check(device->CreateBuffer(&bd,nullptr,&constants));
        ID3D11Buffer* buffers[]={constants.Get()}; context->PSSetConstantBuffers(0,1,buffers);
        UINT aw,ah; auto ap=atlas(argv[2],aw,ah); auto at=texture(device.Get(),aw,ah,ap);
        ComPtr<ID3D11ShaderResourceView> ar; check(device->CreateShaderResourceView(at.Get(),nullptr,&ar));
        std::vector<std::vector<UINT>> sizes={{640,360},{400,600},{400,300}};
        if(argc==4) sizes.push_back({800,450});
        for(auto& size:sizes) {
            UINT w=size[0],h=size[1];
            D3D11_TEXTURE2D_DESC od{}; od.Width=w; od.Height=h; od.MipLevels=od.ArraySize=1;
            od.Format=DXGI_FORMAT_R8G8B8A8_UNORM; od.SampleDesc.Count=1; od.BindFlags=D3D11_BIND_RENDER_TARGET;
            ComPtr<ID3D11Texture2D> out; check(device->CreateTexture2D(&od,nullptr,&out));
            ComPtr<ID3D11RenderTargetView> target; check(device->CreateRenderTargetView(out.Get(),nullptr,&target));
            ID3D11RenderTargetView* targets[]={target.Get()}; context->OMSetRenderTargets(1,targets,nullptr);
            od.BindFlags=0; od.Usage=D3D11_USAGE_STAGING; od.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
            ComPtr<ID3D11Texture2D> staging; check(device->CreateTexture2D(&od,nullptr,&staging));
            D3D11_VIEWPORT viewport{}; viewport.Width=(float)w; viewport.Height=(float)h; viewport.MaxDepth=1;
            context->RSSetViewports(1,&viewport);
            if(w==800) {
                // Documentation-only capture: production HLSL and atlas, simulated
                // anonymous marker states. No key/command data or composited effects.
                // Raw RGBA: 800x450, 20 fps, 120 frames (6 seconds).
                std::ofstream demo(std::filesystem::path(argv[3]),std::ios::binary);
                if(!demo) throw std::runtime_error("Cannot open demo output");
                std::vector<Pixel> input(w*h,Pixel{0,0,0,0});
                auto it=texture(device.Get(),w,h,input);
                ComPtr<ID3D11ShaderResourceView> ir;
                check(device->CreateShaderResourceView(it.Get(),nullptr,&ir));
                ID3D11ShaderResourceView* views[]={ir.Get(),ar.Get()};
                context->PSSetShaderResources(0,2,views);
                for(int frame=0;frame<120;frame++) {
                    float elapsed=frame/20.0f;
                    bool typing=elapsed>=1.50f && elapsed<3.55f &&
                        std::fmod(elapsed-1.50f,0.22f)<0.15f;
                    float fireStart=elapsed>=5.0f?5.0f:3.8f;
                    float fireAge=(elapsed-fireStart)/0.9f;
                    bool fire=fireAge>=0 && fireAge<1;
                    unsigned char blue=fire?(unsigned char)(80+std::min(19,(int)(fireAge*20))):22;
                    input[0]=input[1]=Pixel{5,(unsigned char)(typing?56:8),blue,255};
                    context->UpdateSubresource(it.Get(),0,nullptr,input.data(),w*4,0);
                    Constants c{0.205f+elapsed,1,(float)w,(float)h,{0,0,0,0}};
                    context->UpdateSubresource(constants.Get(),0,nullptr,&c,0,0);
                    context->Draw(3,0); context->CopyResource(staging.Get(),out.Get());
                    D3D11_MAPPED_SUBRESOURCE mapped{};
                    check(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped));
                    for(UINT y=0;y<h;y++) demo.write((char*)mapped.pData+y*mapped.RowPitch,w*4);
                    context->Unmap(staging.Get(),0);
                    if(!demo) throw std::runtime_error("Failed writing demo frame");
                }
                std::cout << "Production shader demo: 800x450, 20 fps, 120 frames\n";
                continue;
            }
            for(float time: {0.205f,1.2f,-100.8f}) {
                Constants c{time,1,(float)w,(float)h,{0,0,0,0}}; // Actual premultiplied default BG.
                context->UpdateSubresource(constants.Get(),0,nullptr,&c,0,0);
                std::vector<Pixel> captures[8];
                for(int on=0;on<8;on++) {
                    c.time = time + ((on==5 || on==6) ? 0.09f : 0.0f);
                    context->UpdateSubresource(constants.Get(),0,nullptr,&c,0,0);
                    std::vector<Pixel> input(w*h,Pixel{0,0,0,0});
                    if(on==1) input[0]=input[1]=Pixel{5,56,22,255};
                    if(on==2) input[0]=input[1]=Pixel{5,8,89,255}; // Anonymous Enter flame only.
                    if(on==3) input[0]=input[1]=Pixel{5,56,89,255}; // Concurrent typing + flame.
                    if(on==4) input[0]=input[1]=Pixel{5,8,83,255}; // Early propagating front.
                    if(on==5) input[0]=input[1]=Pixel{5,8,89,255}; // Same envelope, different animation time.
                    if(on==7) input[0]=input[1]=Pixel{5,8,97,255}; // Throat shut off, outgoing tail remains.
                    // Synthetic bright text in the effect region must remain unchanged.
                    for(UINT y=h/2;y<h/2+8;y++) for(UINT x=w*3/4;x<w*3/4+12;x++) input[y*w+x]=Pixel{199,210,254,255};
                    auto it=texture(device.Get(),w,h,input); ComPtr<ID3D11ShaderResourceView> ir;
                    check(device->CreateShaderResourceView(it.Get(),nullptr,&ir));
                    ID3D11ShaderResourceView* views[]={ir.Get(),ar.Get()}; context->PSSetShaderResources(0,2,views);
                    context->Draw(3,0); context->CopyResource(staging.Get(),out.Get());
                    D3D11_MAPPED_SUBRESOURCE mapped{}; check(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped));
                    captures[on].resize(w*h);
                    for(UINT y=0;y<h;y++) memcpy(&captures[on][y*w],(BYTE*)mapped.pData+y*mapped.RowPitch,w*4);
                    context->Unmap(staging.Get(),0);
                    for(UINT y=h/2;y<h/2+8;y++) for(UINT x=w*3/4;x<w*3/4+12;x++) {
                        Pixel p=captures[on][y*w+x];
                        if(p.r!=199 || p.g!=210 || p.b!=254) throw std::runtime_error("Text readability changed");
                    }
                }
                unsigned green=0, leftGreen=0, rightGreen=0, rightStorm=0;
                for(UINT i=0;i<w*h;i++) {
                    Pixel a=captures[0][i],b=captures[1][i];
                    if((int)b.g-(int)a.g>30 && b.g>(int)b.b+30) {
                        green++;
                        if(i%w<w/3) leftGreen++;
                        if(i%w>w*4/5) rightGreen++;
                    }
                    if(time==0.205f && i%w>w*4/5 && std::max(a.r,std::max(a.g,a.b))>40) rightStorm++;
                }
                if(green<20) throw std::runtime_error("Opaque control cell produced no visible green lightning");
                if(leftGreen<10 || rightGreen<10) throw std::runtime_error("Typing lightning coverage failed: left=" +
                    std::to_string(leftGreen) + ", right=" + std::to_string(rightGreen));
                if(time==0.205f && rightStorm<10) throw std::runtime_error("Ambient storm is still restricted to dragon bounds");
                Pixel marker=captures[1][0];
                if(marker.r!=5 || marker.g!=8 || marker.b!=22) throw std::runtime_error("Control background not hidden");
                unsigned fire=0, combinedGreen=0, nearCount=0, farCount=0;
                UINT earlyEdge=0,lateEdge=0;
                double nearY=0,farY=0,nearY2=0,farY2=0;
                float aspect=(float)w/h;
                float boost=1-std::clamp((aspect-0.95f)/0.5f,0.0f,1.0f);
                boost=boost*boost*(3-2*boost);
                float dw=std::min(0.46f+0.16f*boost,0.86f/aspect);
                float mouth=0.76f-dw*0.06f, length=std::min(dw*0.85f,0.94f-mouth);
                for(UINT i=0;i<w*h;i++) {
                    Pixel a=captures[0][i],b=captures[2][i],both=captures[3][i];
                    Pixel early=captures[4][i];
                    if((int)early.r-(int)a.r>30 && early.r>(int)early.b+30) earlyEdge=std::max(earlyEdge,i%w);
                    if((int)b.r-(int)a.r>30 && b.r>(int)b.b+30) {
                        fire++;
                        lateEdge=std::max(lateEdge,i%w);
                        if(i%w>w*96/100) throw std::runtime_error("Reference fire reached the right window edge");
                        float px=((float)(i%w)/w-mouth)/length;
                        if(px>0.15f && px<0.40f) { nearY+=i/w; nearY2+=(double)(i/w)*(i/w); nearCount++; }
                        if(px>0.65f && px<0.90f) { farY+=i/w; farY2+=(double)(i/w)*(i/w); farCount++; }
                    }
                    if((int)both.g-(int)b.g>30 && both.g>(int)both.b+30) combinedGreen++;
                }
                if(fire<100 || combinedGreen<20) throw std::runtime_error("Enter flame invisible or overwrote typing lightning");
                if(lateEdge<earlyEdge+w/20) throw std::runtime_error("Fire front does not propagate outward from the mouth");
                if(!nearCount || !farCount) throw std::runtime_error("Reference fire has lost its throat or plume");
                double nearSpread=std::sqrt(std::max(0.0,nearY2/nearCount-std::pow(nearY/nearCount,2)));
                double farSpread=std::sqrt(std::max(0.0,farY2/farCount-std::pow(farY/farCount,2)));
                if(farSpread<nearSpread*1.25) throw std::runtime_error("Reference fire no longer widens into a cone");
                unsigned chromaticMotion=0;
                double nearFull=0,nearTail=0,farTail=0;
                for(UINT i=0;i<w*h;i++) {
                    float px=((float)(i%w)/w-mouth)/length;
                    int fullR=std::max(0,(int)captures[2][i].r-(int)captures[0][i].r);
                    int fullG=std::max(0,(int)captures[2][i].g-(int)captures[0][i].g);
                    int movedR=std::max(0,(int)captures[5][i].r-(int)captures[6][i].r);
                    int movedG=std::max(0,(int)captures[5][i].g-(int)captures[6][i].g);
                    int tailR=std::max(0,(int)captures[7][i].r-(int)captures[0][i].r);
                    if(px>0.20f && px<0.85f && fullR>45 && movedR>45 &&
                        std::abs((float)fullG/fullR-(float)movedG/movedR)>0.12f) chromaticMotion++;
                    if(px>0.08f && px<0.28f) { nearFull+=fullR; nearTail+=tailR; }
                    if(px>0.65f && px<0.95f) farTail+=tailR;
                }
                if(chromaticMotion<30) throw std::runtime_error("Fire detail is static or only uniformly flickering");
                if(nearTail>nearFull*0.15 || farTail<500) throw std::runtime_error("Fire shutdown did not travel from mouth to tips");
                std::cout << "Moving internal fire detail: " << chromaticMotion
                    << " chromatic changes; throat shuts off before outgoing tail: PASS\n";
                std::cout << "Pane-wide coverage: left=" << leftGreen << ", right=" << rightGreen
                    << "; flame spread " << nearSpread << " -> " << farSpread << " pixels: PASS\n";
                std::cout << "Enter red flame: " << fire << " red pixels, concurrent green lightning preserved: PASS\n";
                std::cout << "WARP " << w << "x" << h << " time=" << time << ": " << green
                    << " green pixels; transparent BG, marker cleanup and text preservation: PASS\n";
            }
        }
        CoUninitialize(); return 0;
    } catch(const std::exception& e) {std::cerr << e.what() << '\n'; return 1;}
}


