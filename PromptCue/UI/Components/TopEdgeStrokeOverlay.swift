import SwiftUI

struct TopEdgeStrokeOverlay<Shape: InsettableShape>: View {
    let shape: Shape
    let color: Color
    let lineWidth: CGFloat
    let frameHeight: CGFloat
    let maskHeight: CGFloat

    var body: some View {
        shape
            .stroke(color, lineWidth: lineWidth)
            .frame(height: frameHeight)
            .mask(alignment: .top) {
                Rectangle()
                    .frame(height: maskHeight)
            }
    }
}
