import SwiftUI

struct LuckyCatEdgeRail3DChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var shape: Capsule {
        Capsule(style: .continuous)
    }

    var body: some View {
        ZStack {
            floatingShadowLayer
            contactShadowLayer

            ZStack(alignment: .trailing) {
                environmentBackgroundLayer
                blurredBackgroundTexture
                backgroundLiftPlate
                glassCardBase
                centerLuminosityField
                fullBodyRefractionVeil
                subsurfaceDiffusionLayer
                refractedEdgeField
                normalRefractionLayer
                edgeThicknessBand
                sdfEdgeCutHighlight
                fresnelRimLight
                bottomRefractionEdge
                sideThickness
                contentReadabilityPlate
                straightEdgeHighlightLayer
                straightEdgeDimLayer
                microNoiseLayer
                contentPerspectiveLayer
            }
            .clipShape(shape)
            .overlay(innerRefraction)
            .overlay(topSoftGlow)
            .overlay(capLensSurfaceLayer)
            .overlay(topArcRim)
            .overlay(bottomArcRim)
            .overlay(capContourRim)
            .overlay(diagonalLightBand)
            .overlay(outerEdgeHighlight)
            .overlay(leftCutHighlight)
            .overlay(rightCutHighlight)
            .overlay(silhouetteOutline)
        }
        .frame(width: LuckyCatLayout.edgeRailWidth, height: LuckyCatLayout.edgeRailHeight)
        .frame(width: LuckyCatLayout.edgeRailPanelWidth, height: LuckyCatLayout.edgeRailPanelHeight)
    }
}
