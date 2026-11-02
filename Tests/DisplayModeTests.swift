import Foundation
import AppKit
@main struct DisplayModeTests {
 static func main() throws {
  func check(_ condition:Bool,_ name:String) { precondition(condition,name); print("PASS \(name)") }
  let suite="Quota.DisplayTests.\(UUID().uuidString)";let d=UserDefaults(suiteName:suite)!
  defer {d.removePersistentDomain(forName:suite)}
  check(StatusDisplayMode.restored(from:d) == .both,"fresh install preserves compact both-services default")
  d.set(false,forKey:"compactDual")
  check(StatusDisplayMode.restored(from:d) == .codex,"old single-service preference migrates to Codex")
  for mode in StatusDisplayMode.allCases {
   d.set(mode.rawValue,forKey:"statusDisplayMode")
   check(StatusDisplayMode.restored(from:UserDefaults(suiteName:suite)!) == mode,"\(mode.rawValue) survives preferences reload")
  }
  check(StatusDisplayMode.codex.target(codex:20,antigravity:80)==20,"Codex mode uses Codex quota")
  check(StatusDisplayMode.antigravity.target(codex:20,antigravity:80)==80,"Antigravity mode uses AG quota rather than Codex")
  check(StatusDisplayMode.antigravity.target(codex:20,antigravity:nil)==nil,"unavailable AG never falls back to Codex")
  var single=Set<Data>(),dual=Set<Data>()
  for style in StatusIconStyle.allCases {
   func png(_ image:NSImage)->Data {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:104,pixelsHigh:80,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    NSGraphicsContext.current?.cgContext.scaleBy(x:4,y:4)
    image.draw(in:NSRect(x:0,y:0,width:26,height:20));NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
   }
   single.insert(png(StatusIconRenderer.image(style:style,remaining:20)))
   let combined=StatusIconRenderer.combined(style:style,codex:20,gravity:80)
   dual.insert(png(combined))
   check(png(combined) != png(StatusIconRenderer.combined(style:style,codex:80,gravity:20)),"\(style.rawValue) combined icon preserves service positions independently")
  }
  check(single.count==3 && dual.count==3,"all three styles visually distinct in both single and dual modes")
  check(PanelTheme.restored(from:d) == .bento,"fresh install defaults to Bento dual-core theme")
  for theme in PanelTheme.allCases {
   d.set(theme.rawValue,forKey:"panelTheme")
   check(PanelTheme.restored(from:UserDefaults(suiteName:suite)!) == theme,"\(theme.rawValue) theme survives preferences reload")
  }
  d.set("unknown-theme",forKey:"panelTheme")
  check(PanelTheme.restored(from:d) == .bento,"unknown stored theme falls back safely to Bento")
 }
}
