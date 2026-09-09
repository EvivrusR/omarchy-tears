import QtQuick
import QtQuick.Shapes
import qs.Commons

// A filled sparkline. `points` are normalised {x: 0..1 (1 = now), y: 0..1}.
// Drawn with a dark outline under the line so it reads on any wallpaper.
Item {
  id: spark
  property var points: []
  property color lineColor: "white"
  property color outlineColor: "#000000"
  property real fillAlpha: 0.25
  property real lineWidth: 2

  function px(p) { return p.x * width }
  function py(p) { return height - p.y * (height - lineWidth) - lineWidth / 2 }
  readonly property var pts: {
    var out = []
    var list = points || []
    for (var i = 0; i < list.length; i++) out.push({ x: px(list[i]), y: py(list[i]) })
    return out
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    visible: spark.pts.length > 1
    // filled area
    ShapePath {
      strokeWidth: 0; strokeColor: "transparent"
      fillColor: Util.alpha(spark.lineColor, spark.fillAlpha)
      startX: spark.pts.length ? spark.pts[0].x : 0; startY: spark.height
      PathPolyline { path: spark.pts.length ? [Qt.point(spark.pts[0].x, spark.height)].concat(spark.pts.map(function(p) { return Qt.point(p.x, p.y) })).concat([Qt.point(spark.pts[spark.pts.length - 1].x, spark.height)]) : [] }
    }
    // dark outline under the line
    ShapePath {
      strokeWidth: spark.lineWidth + 2; strokeColor: spark.outlineColor.a > 0 ? Util.alpha(spark.outlineColor, 0.8) : "transparent"; fillColor: "transparent"
      capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
      startX: spark.pts.length ? spark.pts[0].x : 0; startY: spark.pts.length ? spark.pts[0].y : 0
      PathPolyline { path: spark.pts.map(function(p) { return Qt.point(p.x, p.y) }) }
    }
    ShapePath {
      strokeWidth: spark.lineWidth; strokeColor: spark.lineColor; fillColor: "transparent"
      capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
      startX: spark.pts.length ? spark.pts[0].x : 0; startY: spark.pts.length ? spark.pts[0].y : 0
      PathPolyline { path: spark.pts.map(function(p) { return Qt.point(p.x, p.y) }) }
    }
  }
  // baseline
  Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: spark.outlineColor.a > 0 ? Util.alpha(spark.outlineColor, 0.5) : Util.alpha(spark.lineColor, 0.3) }
}
