import Foundation

// OWNER: FAM-F2. Skeleton stub; the owner fills it. The type name `F2Catalog` is frozen (Registry.swift).
// Entries: gaussian-blur (written by SKEL first), binomial-blur, iir-gaussian; unsharp-mask, difference-of-gaussians, lanczos (T3).
public enum F2Catalog {
    public static let operators: [any BlurOperator] = [GaussianOperator()]
}
