import Foundation
@main struct AGTests {
 static func main() throws {
  func check(_ condition:Bool,_ name:String) { precondition(condition,name); print("PASS \(name)") }
  let raw = #"{"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[{"label":"A","quotaInfo":{"remainingFraction":0.5,"resetTime":"2099-01-01T00:00:00.123Z"}},{"label":"A","quotaInfo":{"remainingFraction":0.2}},{"label":"B","quotaInfo":{"remainingFraction":0}},{"label":"Invalid","quotaInfo":{"remainingFraction":true}},{"label":"Bad","quotaInfo":{"remainingFraction":1.5}},{"label":"Available without quota"}]}}}"#
  let values=try AGClient.parse(Data(raw.utf8))
  check(values.count==2,"model availability and invalid values never become measured quota")
  check(values.first{$0.name=="A"}?.remaining==20,"duplicate identities use conservative remaining quota")
  check(values.first{$0.name=="B"}?.remaining==0,"zero is a valid quota, not missing data")
  do { _=try AGClient.parse(Data("{}".utf8));preconditionFailure("must reject empty") } catch { print("PASS empty response remains unavailable") }
  let report = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini","buckets":[{"name":"五小时","remaining_fraction":0.75},{"name":"每周","remaining_fraction":0.4},{"name":"Disabled","remaining_fraction":1,"disabled":true},{"name":"Unknown"}]}]}}}"#
  let parsed = try AGCLI.parse(Data(report.utf8))
  check(parsed.count == 2 && parsed.map(\.remaining).min() == 40,"CLI report preserves independent measured buckets and excludes disabled/unknown")
  do { _=try AGCLI.parse(Data(report.replacingOccurrences(of:"SUCCESS",with:"ERROR").utf8));preconditionFailure("must reject failed report") } catch { print("PASS failed CLI report cannot supply quota") }
  do { _=try AGCLI.parse(Data(report.replacingOccurrences(of:"usage",with:"other-command").utf8));preconditionFailure("must reject non-usage report") } catch { print("PASS non-usage command cannot supply quota") }

  let now=Date()
  let grouped=[AGQuota(name:"g5",remaining:80,reset:now.addingTimeInterval(100),group:"Gemini Models",window:"5h"),AGQuota(name:"gw",remaining:40,reset:now.addingTimeInterval(100),group:"Gemini Models",window:"weekly"),AGQuota(name:"cw",remaining:0,reset:nil,group:"Claude and GPT models",window:"weekly")]
  check(AGQuota.overview(grouped,group:"Gemini Models",now:now)==40,"selected group uses its tighter window without contamination from another group")
  check(AGQuota.overview(grouped,group:"Claude and GPT models",now:now)==0,"switching group includes genuine exhausted quota")
  check(AGQuota.overview(grouped,group:"missing",now:now)==nil,"missing group cannot appear full")
  check(AGQuota.overview(grouped,group:"Gemini Models",now:now.addingTimeInterval(101))==nil,"expired window is unknown rather than silently excluded")
  check(Set(parsed.map(\.window)) == Set(["5h","weekly"]),"window metadata survives parsing for separate Chinese rows")

 }
}
