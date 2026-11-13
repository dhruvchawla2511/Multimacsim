import Foundation

/// A high-performance 2D matrix structure designed for circuit simulation (MNA).
/// Includes Gaussian Elimination with Partial Pivoting and LU Decomposition.
public struct Matrix: Equatable {
    public let rows: Int
    public let cols: Int
    public var data: [Double]

    public init(rows: Int, cols: Int, initialValue: Double = 0.0) {
        self.rows = rows
        self.cols = cols
        self.data = [Double](repeating: initialValue, count: rows * cols)
    }

    public init(rows: Int, cols: Int, data: [Double]) {
        precondition(data.count == rows * cols, "Data count must match rows * cols")
        self.rows = rows
        self.cols = cols
        self.data = data
    }

    @inline(__always)
    public subscript(row: Int, col: Int) -> Double {
        get {
            assert(row >= 0 && row < rows && col >= 0 && col < cols, "Index out of bounds")
            return data[row * cols + col]
        }
        set {
            assert(row >= 0 && row < rows && col >= 0 && col < cols, "Index out of bounds")
            data[row * cols + col] = newValue
        }
    }

    /// Sets all elements to zero.
    public mutating func clear() {
        for i in 0..<data.count {
            data[i] = 0.0
        }
    }

    /// Solves the linear system A * x = b using Gaussian Elimination with Partial Pivoting.
    /// Returns nil if the matrix is singular or non-invertible.
    public func solve(b: [Double]) -> [Double]? {
        precondition(rows == cols, "Matrix must be square to solve A * x = b")
        precondition(b.count == rows, "Vector b dimension must match matrix rows")

        let n = rows
        if n == 0 { return [] }

        // Create augmented matrix [A | b]
        var a = self
        var x = b

        for p in 0..<n {
            // Find pivot row with largest absolute value in column p
            var maxVal = abs(a[p, p])
            var pivotRow = p
            for i in (p + 1)..<n {
                let val = abs(a[i, p])
                if val > maxVal {
                    maxVal = val
                    pivotRow = i
                }
            }

            // Check for singularity (zero pivot)
            if maxVal < 1e-14 {
                return nil
            }

            // Swap rows in A and b if needed
            if pivotRow != p {
                for col in 0..<n {
                    let temp = a[p, col]
                    a[p, col] = a[pivotRow, col]
                    a[pivotRow, col] = temp
                }
                let tempB = x[p]
                x[p] = x[pivotRow]
                x[pivotRow] = tempB
            }

            // Eliminate lower rows
            let pivot = a[p, p]
            for i in (p + 1)..<n {
                let factor = a[i, p] / pivot
                if factor != 0.0 {
                    for j in p..<n {
                        a[i, j] -= factor * a[p, j]
                    }
                    x[i] -= factor * x[p]
                }
            }
        }

        // Back-substitution
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = x[i]
            for j in (i + 1)..<n {
                sum -= a[i, j] * x[j]
            }
            let diag = a[i, i]
            if abs(diag) < 1e-14 {
                return nil
            }
            x[i] = sum / diag
        }

        return x
    }
}
