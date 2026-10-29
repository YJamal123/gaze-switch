import Foundation

/// A linear map from features to outputs, fitted with ridge regression on standardized features.
public struct LinearModel: Codable, Equatable {
    public var mean: [Double]
    public var scale: [Double]
    /// One row per output: the bias followed by one weight per standardized feature.
    public var weights: [[Double]]

    public func predict(_ x: [Double]) -> [Double] {
        precondition(x.count == mean.count, "feature count mismatch")
        return weights.map { row in
            var y = row[0]
            for i in 0..<x.count { y += row[i + 1] * (x[i] - mean[i]) / scale[i] }
            return y
        }
    }

    /// `lambda` is relative to the sample count, so 0.05 shrinks the weights by roughly 5%.
    public static func fit(inputs: [[Double]], outputs: [[Double]], lambda: Double = 0.05) -> LinearModel? {
        guard let d = inputs.first?.count, d > 0, inputs.count > d, inputs.count == outputs.count,
              let k = outputs.first?.count, k > 0 else { return nil }
        let n = Double(inputs.count)

        var mean = [Double](repeating: 0, count: d)
        for x in inputs { for i in 0..<d { mean[i] += x[i] } }
        mean = mean.map { $0 / n }
        var scale = [Double](repeating: 0, count: d)
        for x in inputs { for i in 0..<d { scale[i] += (x[i] - mean[i]) * (x[i] - mean[i]) } }
        scale = scale.map { let s = ($0 / n).squareRoot(); return s > 1e-9 ? s : 1 }

        // Normal equations over design rows [1, z1 ... zd]; the bias is not regularized.
        let m = d + 1
        var ata = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        var aty = [[Double]](repeating: [Double](repeating: 0, count: k), count: m)
        var row = [Double](repeating: 1, count: m)
        for (x, y) in zip(inputs, outputs) {
            for i in 0..<d { row[i + 1] = (x[i] - mean[i]) / scale[i] }
            for a in 0..<m {
                for b in 0..<m { ata[a][b] += row[a] * row[b] }
                for j in 0..<k { aty[a][j] += row[a] * y[j] }
            }
        }
        // A small floor keeps the system solvable when a feature never changes or two move in lockstep.
        for a in 1..<m { ata[a][a] += max(lambda, 1e-6) * n }

        guard let w = solve(ata, aty) else { return nil }
        let weights = (0..<k).map { j in (0..<m).map { w[$0][j] } }
        return LinearModel(mean: mean, scale: scale, weights: weights)
    }
}

/// Solves A·X = B by Gauss-Jordan elimination with partial pivoting.
func solve(_ a: [[Double]], _ b: [[Double]]) -> [[Double]]? {
    var a = a, b = b
    let n = a.count
    for col in 0..<n {
        let pivot = (col..<n).max { abs(a[$0][col]) < abs(a[$1][col]) }!
        guard abs(a[pivot][col]) > 1e-12 else { return nil }
        a.swapAt(col, pivot)
        b.swapAt(col, pivot)
        for r in 0..<n where r != col {
            let f = a[r][col] / a[col][col]
            if f == 0 { continue }
            for c in col..<n { a[r][c] -= f * a[col][c] }
            for j in 0..<b[r].count { b[r][j] -= f * b[col][j] }
        }
    }
    for r in 0..<n {
        let p = a[r][r]
        for j in 0..<b[r].count { b[r][j] /= p }
    }
    return b
}
