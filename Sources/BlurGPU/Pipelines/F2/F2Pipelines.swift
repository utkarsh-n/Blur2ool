import Foundation
import Metal
import BlurCore

// OWNER: FAM-F2. Skeleton seeds; the owner fills the rest. The type name `F2Pipelines` is frozen (GPUBlurPipeline.swift).
// TODO(FAM-F2): gaussian-2d-direct, binomial-blur, iir-gaussian, unsharp-mask, difference-of-gaussians pipelines.
public enum F2Pipelines {
    public static let factories: [GPUPipelineFactory] = [
        GPUPipelineFactory(blur: "gaussian-blur", variant: "gaussian-linear-sampling", make: { GaussianLinearPipeline() },
                           parityCases: GaussianLinearPipeline.parityCases),
        GPUPipelineFactory(blur: "gaussian-blur", variant: "gaussian-separable", make: { GaussianSeparablePipeline() },
                           parityCases: GaussianSeparablePipeline.parityCases),
        GPUPipelineFactory(blur: "gaussian-blur", variant: "gaussian-compute-tile", make: { GaussianComputeTilePipeline() },
                           parityCases: GaussianComputeTilePipeline.parityCases),
    ]
}
