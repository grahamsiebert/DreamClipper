import SwiftUI

struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    
    @State private var width: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                
                // Selected Range
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.accent)
                    .frame(width: max(0, (CGFloat(end - start) / CGFloat(range.upperBound - range.lowerBound)) * geometry.size.width), height: 4)
                    .offset(x: (CGFloat(start - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)) * geometry.size.width)
                
                // Start Handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: (CGFloat(start - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)) * geometry.size.width - 10)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                onEditingChanged(true)
                                let location = value.location.x
                                let percentage = location / geometry.size.width
                                let newValue = range.lowerBound + Double(percentage) * (range.upperBound - range.lowerBound)
                                start = min(max(range.lowerBound, newValue), end)
                            }
                            .onEnded { _ in
                                onEditingChanged(false)
                            }
                    )
                
                // End Handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: (CGFloat(end - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)) * geometry.size.width - 10)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                onEditingChanged(true)
                                let location = value.location.x
                                let percentage = location / geometry.size.width
                                let newValue = range.lowerBound + Double(percentage) * (range.upperBound - range.lowerBound)
                                end = max(min(range.upperBound, newValue), start)
                            }
                            .onEnded { _ in
                                onEditingChanged(false)
                            }
                    )
            }
            .onAppear {
                width = geometry.size.width
            }
        }
        .frame(height: 30)
    }
}
