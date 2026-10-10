// Documentation renderer: exact production HLSL, matching texture and terminal text.
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <vector>
#include <string>
#include <iostream>
#include <stdexcept>
#include <cstring>
#include <filesystem>
#include <cmath>
using Microsoft::WRL::ComPtr;
void check(HRESULT hr) { if (FAILED(hr)) throw std::runtime_error("Graphics call failed: " + std::to_string(hr)); }
struct Pixel { unsigned char r,g,b,a; };
struct Constants { float time,scale,width,height,background[4]; };
std::vector<Pixel> load(IWICImagingFactory* factory,const wchar_t* path,UINT& w,UINT& h) {
    ComPtr<IWICBitmapDecoder> decoder;
    check(factory->CreateDecoderFromFilename(path,nullptr,GENERIC_READ,WICDecodeMetadataCacheOnLoad,&decoder));
    ComPtr<IWICBitmapFrameDecode> frame; check(decoder->GetFrame(0,&frame)); check(frame->GetSize(&w,&h));
    ComPtr<IWICFormatConverter> converter; check(factory->CreateFormatConverter(&converter));
    check(converter->Initialize(frame.Get(),GUID_WICPixelFormat32bppPRGBA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom));
    std::vector<Pixel> pixels(w*h);
    check(converter->CopyPixels(nullptr,w*4,(UINT)pixels.size()*4,(BYTE*)pixels.data()));
    return pixels;
}
ComPtr<ID3D11Texture2D> texture(ID3D11Device* device,UINT w,UINT h,const std::vector<Pixel>& pixels) {
    D3D11_TEXTURE2D_DESC d{}; d.Width=w;d.Height=h;d.MipLevels=d.ArraySize=1;
    d.Format=DXGI_FORMAT_R8G8B8A8_UNORM;d.SampleDesc.Count=1;d.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA data{};data.pSysMem=pixels.data();data.SysMemPitch=w*4;
    ComPtr<ID3D11Texture2D> t;check(device->CreateTexture2D(&d,&data,&t));return t;
}
void save(IWICImagingFactory* factory,const wchar_t* path,UINT w,UINT h,std::vector<Pixel>& pixels) {
    ComPtr<IWICStream> stream;check(factory->CreateStream(&stream));
    check(stream->InitializeFromFilename(path,GENERIC_WRITE));
    ComPtr<IWICBitmapEncoder> encoder;check(factory->CreateEncoder(GUID_ContainerFormatPng,nullptr,&encoder));
    check(encoder->Initialize(stream.Get(),WICBitmapEncoderNoCache));
    ComPtr<IWICBitmapFrameEncode> frame;ComPtr<IPropertyBag2> props;
    check(encoder->CreateNewFrame(&frame,&props));check(frame->Initialize(props.Get()));
    check(frame->SetSize(w,h));WICPixelFormatGUID format=GUID_WICPixelFormat32bppRGBA;
    check(frame->SetPixelFormat(&format));
    for(auto& p:pixels) p.a=255;
    // WIC PNG negotiates its native channel order (commonly BGRA).
    ComPtr<IWICBitmap> bitmap;
    check(factory->CreateBitmapFromMemory(w,h,GUID_WICPixelFormat32bppRGBA,w*4,
        (UINT)pixels.size()*4,(BYTE*)pixels.data(),&bitmap));
    ComPtr<IWICFormatConverter> converter;check(factory->CreateFormatConverter(&converter));
    check(converter->Initialize(bitmap.Get(),format,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom));
    check(frame->WriteSource(converter.Get(),nullptr));
    check(frame->Commit());check(encoder->Commit());
}
int wmain(int argc,wchar_t** argv) {
    try {
        if(argc!=6) throw std::runtime_error("Expected shader, texture, terminal PNG, output PNG, input-effects flag");
        check(CoInitializeEx(nullptr,COINIT_MULTITHREADED));
        ComPtr<IWICImagingFactory> factory;
        check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
        UINT w,h,aw,ah;auto terminal=load(factory.Get(),argv[3],w,h);auto image=load(factory.Get(),argv[2],aw,ah);
        if(w!=1280||h!=720)throw std::runtime_error("Expected 1280x720 terminal input");
        bool effects=std::wstring(argv[5])==L"1";
        if(effects) terminal[0]=terminal[1]=Pixel{5,56,89,255}; // Simulated typing and mid-breath.
        ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> context;
        check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&device,nullptr,&context));
        ComPtr<ID3DBlob> code,errors;
        HRESULT hr=D3DCompileFromFile(argv[1],nullptr,nullptr,"main","ps_4_0",2048,0,&code,&errors);
        if(FAILED(hr)&&errors)std::cerr<<(const char*)errors->GetBufferPointer();check(hr);
        ComPtr<ID3D11PixelShader> ps;check(device->CreatePixelShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&ps));
        const char* vsSource="struct V{float4 p:SV_POSITION;float2 u:TEXCOORD0;};"
            "V main(uint i:SV_VertexID){V v;float2 u=float2((i<<1)&2,i&2);"
            "v.p=float4(u.x*2-1,1-u.y*2,0,1);v.u=u;return v;}";
        check(D3DCompile(vsSource,strlen(vsSource),nullptr,nullptr,nullptr,"main","vs_4_0",0,0,&code,&errors));
        ComPtr<ID3D11VertexShader> vs;check(device->CreateVertexShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&vs));
        context->VSSetShader(vs.Get(),nullptr,0);context->PSSetShader(ps.Get(),nullptr,0);
        context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        auto it=texture(device.Get(),w,h,terminal),at=texture(device.Get(),aw,ah,image);
        ComPtr<ID3D11ShaderResourceView> ir,ar;check(device->CreateShaderResourceView(it.Get(),nullptr,&ir));
        check(device->CreateShaderResourceView(at.Get(),nullptr,&ar));
        ID3D11ShaderResourceView* views[]={ir.Get(),ar.Get()};context->PSSetShaderResources(0,2,views);
        D3D11_SAMPLER_DESC sd{};sd.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP;sd.MaxLOD=D3D11_FLOAT32_MAX;
        ComPtr<ID3D11SamplerState> sampler;check(device->CreateSamplerState(&sd,&sampler));
        ID3D11SamplerState* samplers[]={sampler.Get()};context->PSSetSamplers(0,1,samplers);
        Constants c{0.205f,1,(float)w,(float)h,{5.0f/255,8.0f/255,22.0f/255,1}};
        D3D11_BUFFER_DESC bd{};bd.ByteWidth=sizeof(Constants);bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        D3D11_SUBRESOURCE_DATA data{};data.pSysMem=&c;
        ComPtr<ID3D11Buffer> cb;check(device->CreateBuffer(&bd,&data,&cb));ID3D11Buffer* buffers[]={cb.Get()};
        context->PSSetConstantBuffers(0,1,buffers);
        D3D11_TEXTURE2D_DESC od{};od.Width=w;od.Height=h;od.MipLevels=od.ArraySize=1;
        od.Format=DXGI_FORMAT_R8G8B8A8_UNORM;od.SampleDesc.Count=1;od.BindFlags=D3D11_BIND_RENDER_TARGET;
        ComPtr<ID3D11Texture2D> out;check(device->CreateTexture2D(&od,nullptr,&out));
        ComPtr<ID3D11RenderTargetView> target;check(device->CreateRenderTargetView(out.Get(),nullptr,&target));
        ID3D11RenderTargetView* targets[]={target.Get()};context->OMSetRenderTargets(1,targets,nullptr);
        D3D11_VIEWPORT viewport{};viewport.Width=(float)w;viewport.Height=(float)h;viewport.MaxDepth=1;
        context->RSSetViewports(1,&viewport);context->Draw(3,0);
        od.BindFlags=0;od.Usage=D3D11_USAGE_STAGING;od.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        ComPtr<ID3D11Texture2D> staging;check(device->CreateTexture2D(&od,nullptr,&staging));context->CopyResource(staging.Get(),out.Get());
        D3D11_MAPPED_SUBRESOURCE mapped{};check(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped));
        std::vector<Pixel> pixels(w*h);for(UINT y=0;y<h;y++)memcpy(&pixels[y*w],(BYTE*)mapped.pData+y*mapped.RowPitch,w*4);
        context->Unmap(staging.Get(),0);
        // Verify bright sample text stays visible, including legacy renderers.
        unsigned text=0,art=0;
        for(UINT y=0;y<h;y++)for(UINT x=0;x<w;x++){
            auto p=pixels[y*w+x];
            if(x<700&&terminal[y*w+x].r>160&&p.r>140)text++;
            if(x>800&&(p.b>45||p.r>60||p.g>50))art++;
        }
        if(text<1000||art<1000)throw std::runtime_error("Gallery lost prompt text or visible artwork");
        save(factory.Get(),argv[4],w,h,pixels);
        std::cout<<"Production shader terminal preview: "<<w<<"x"<<h<<std::endl;
        // Keep COM alive until local WIC smart pointers have released their objects.
        return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}

