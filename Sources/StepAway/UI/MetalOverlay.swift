import MetalKit
import SwiftUI

enum OverlayStyle: String, CaseIterable, Codable {
    case aurora
    case plasma
    case rays

    var title: String {
        switch self {
        case .aurora: return "极光 Aurora"
        case .plasma: return "等离子 Plasma"
        case .rays: return "射线 Rays"
        }
    }

    var functionName: String { "overlay_\(rawValue)" }

    var colors: (SIMD3<Float>, SIMD3<Float>) {
        switch self {
        case .aurora: return (SIMD3(0.05, 0.10, 0.22), SIMD3(0.10, 0.55, 0.48))
        case .plasma: return (SIMD3(0.16, 0.05, 0.28), SIMD3(0.85, 0.25, 0.45))
        case .rays: return (SIMD3(0.10, 0.07, 0.05), SIMD3(0.95, 0.62, 0.30))
        }
    }

    /// "auto" rotates the effects between breaks so a long day does not show the
    /// same animation every time.
    static func resolve(preference: String, cycleIndex: Int) -> OverlayStyle {
        if let exact = OverlayStyle(rawValue: preference) { return exact }
        let all = OverlayStyle.allCases
        return all[abs(cycleIndex) % all.count]
    }
}

struct OverlayUniforms {
    var time: Float = 0
    var progress: Float = 0
    var aspect: Float = 1
    var pad0: Float = 0
    var colorA: SIMD3<Float> = .zero
    var pad1: Float = 0
    var colorB: SIMD3<Float> = .zero
    var pad2: Float = 0
}

/// The Metal toolchain ships with Xcode, not with the Command Line Tools, so the
/// shader source is compiled at runtime instead of from a prebuilt .metallib.
final class OverlayMetal {
    static let shared = OverlayMetal()

    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var library: MTLLibrary?
    private var pipelines: [String: MTLRenderPipelineState] = [:]

    var isAvailable: Bool { device != nil && library != nil }

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.queue = device?.makeCommandQueue()
        if let device {
            library = try? device.makeLibrary(source: OverlayShaders.source, options: nil)
        }
    }

    func makePipeline(style: OverlayStyle, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        guard let device, let library,
              let vertex = library.makeFunction(name: "overlay_vertex"),
              let fragment = library.makeFunction(name: style.functionName)
        else { return nil }

        let key = "\(style.rawValue)-\(pixelFormat.rawValue)"
        if let cached = pipelines[key] { return cached }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let created = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        pipelines[key] = created
        return created
    }

    func makeRenderer(style: OverlayStyle, pixelFormat: MTLPixelFormat) -> OverlayRenderer? {
        guard let queue, let pipeline = makePipeline(style: style, pixelFormat: pixelFormat) else { return nil }
        let colors = style.colors
        return OverlayRenderer(queue: queue, pipeline: pipeline, colorA: colors.0, colorB: colors.1)
    }

    /// Renders one frame offscreen and returns the raw BGRA bytes. Used by
    /// `--selftest` because this host's screen capture cannot see app windows.
    func renderSample(style: OverlayStyle, size: Int = 64) -> Data? {
        guard let device, let queue,
              let pipeline = makePipeline(style: style, pixelFormat: .bgra8Unorm)
        else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor),
              let buffer = queue.makeCommandBuffer()
        else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniforms = OverlayUniforms(
            time: 1.7,
            progress: 0.5,
            aspect: 1,
            colorA: style.colors.0,
            colorB: style.colors.1
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OverlayUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(&bytes, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return Data(bytes)
    }
}

final class OverlayRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let startedAt = CACurrentMediaTime()
    private let colorA: SIMD3<Float>
    private let colorB: SIMD3<Float>

    var progress: Float = 0

    init(queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, colorA: SIMD3<Float>, colorB: SIMD3<Float>) {
        self.queue = queue
        self.pipeline = pipeline
        self.colorA = colorA
        self.colorB = colorB
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let passDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        var uniforms = OverlayUniforms(
            time: Float(CACurrentMediaTime() - startedAt),
            progress: progress,
            aspect: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
            colorA: colorA,
            colorB: colorB
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OverlayUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

struct MetalOverlayBackground: NSViewRepresentable {
    let style: OverlayStyle
    let progress: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = OverlayMetal.shared.device,
              let renderer = OverlayMetal.shared.makeRenderer(style: style, pixelFormat: .bgra8Unorm)
        else { return view }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        // CVDisplayLink does not tick on every host (notably virtual displays), so
        // frames are driven by an explicit timer instead.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        renderer.progress = Float(progress)
        context.coordinator.renderer = renderer
        context.coordinator.start(view: view)
        view.delegate = renderer
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.progress = Float(progress)
        context.coordinator.start(view: view)
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.delegate = nil
    }

    final class Coordinator {
        var renderer: OverlayRenderer?
        private var timer: Timer?

        func start(view: MTKView) {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak view] _ in
                view?.draw()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }
    }
}

enum OverlayShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float time;
        float progress;
        float aspect;
        float pad0;
        float3 colorA;
        float pad1;
        float3 colorB;
        float pad2;
    };

    vertex VertexOut overlay_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VertexOut out;
        float2 p = positions[vid];
        out.position = float4(p, 0.0, 1.0);
        out.uv = p * 0.5 + 0.5;
        return out;
    }

    inline float overlay_hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    inline float overlay_noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 w = f * f * (3.0 - 2.0 * f);
        float a = overlay_hash(i);
        float b = overlay_hash(i + float2(1.0, 0.0));
        float c = overlay_hash(i + float2(0.0, 1.0));
        float d = overlay_hash(i + float2(1.0, 1.0));
        return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
    }

    inline float overlay_fbm(float2 p) {
        float value = 0.0;
        float amplitude = 0.5;
        for (int i = 0; i < 5; i++) {
            value += amplitude * overlay_noise(p);
            p *= 2.02;
            amplitude *= 0.5;
        }
        return value;
    }

    fragment float4 overlay_aurora(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = float2(in.uv.x * u.aspect, in.uv.y);
        float t = u.time * 0.12;
        float n = overlay_fbm(uv * 1.8 + float2(t, -t * 0.6));
        float band = 0.5 + 0.5 * sin((uv.y * 2.6 + n * 2.4 + t * 2.0) * 3.14159);
        float3 color = mix(u.colorA, u.colorB, band);
        color += pow(band, 3.0) * float3(0.10, 0.35, 0.30);
        float vignette = smoothstep(1.25, 0.25, length(uv - float2(u.aspect * 0.5, 0.5)));
        color *= mix(0.55, 1.0, vignette);
        color *= clamp(u.progress * 8.0, 0.35, 1.0);
        return float4(color, 1.0);
    }

    fragment float4 overlay_plasma(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = float2(in.uv.x * u.aspect, in.uv.y);
        float t = u.time * 0.5;
        float v = sin(uv.x * 4.0 + t)
                + sin(uv.y * 5.0 - t * 0.8)
                + sin((uv.x + uv.y) * 3.0 + t * 0.6)
                + sin(length(uv - float2(u.aspect * 0.5, 0.5)) * 9.0 - t * 1.3);
        v *= 0.25;
        float3 color = mix(u.colorA, u.colorB, 0.5 + 0.5 * v);
        color *= clamp(u.progress * 8.0, 0.35, 1.0);
        return float4(color, 1.0);
    }

    fragment float4 overlay_rays(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = float2(in.uv.x * u.aspect, in.uv.y);
        float2 c = uv - float2(u.aspect * 0.5, 0.5);
        float angle = atan2(c.y, c.x);
        float radius = length(c);
        float rays = 0.5 + 0.5 * sin(angle * 14.0 + u.time * 0.35 + radius * 5.0);
        float3 color = mix(u.colorA, u.colorB, rays);
        float fade = smoothstep(1.1, 0.15, radius / max(u.aspect, 1.0));
        color *= mix(0.45, 1.0, fade);
        color *= clamp(u.progress * 8.0, 0.35, 1.0);
        return float4(color, 1.0);
    }
    """
}
