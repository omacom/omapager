import QtQuick
import Quickshell
import qs.Commons
import "Plugin" as Plugin

Window {
  id: test
  visible: true
  width: 500
  height: 1600
  color: "#eeeeee"

  property int requestedReplies: 0
  property int stackDismissals: 0
  property string invokedAction: ""
  property var cases: []
  property int index: -1
  property string phase: "start"
  property real visibleCardHeight: 0
  readonly property string profile: Quickshell.env("OMAPAGER_TEST_PROFILE") || "default"

  Plugin.Toast {
    id: toast
    cardWidth: 340
    place: ({front: true, count: 1, z: 1})
    expanded: true
    hovered: true
    paused: true
    onReplyRequested: test.requestedReplies++
    onActionInvoked: identifier => test.invokedAction = identifier
    onStackDismissed: test.stackDismissals++
  }

  TextMetrics {
    id: titleMeasure
    text: String(toast.row.summary || "")
  }

  function check(ok, message) {
    if (!ok) throw new Error(profile + " case " + index + " " + phase + ": " + message)
  }
  function walk(item, out) {
    out.push(item)
    if (item.children) for (var child of item.children) walk(child, out)
  }
  function nodes(item) { var out=[]; walk(item, out); return out }
  function buttons() { return nodes(toast).filter(n => n.deed !== undefined && n.visible) }
  function labelOf(button) {
    var text = button.labelText === undefined ? button.text : button.labelText
    var labels = nodes(button).filter(n => n !== button && n.text === text && n.lineCount !== undefined && n.visible)
    check(labels.length === 1, "expected one rendered label for " + text)
    return labels[0]
  }
  function inside(item, ancestor, message) {
    var p=item.mapToItem(ancestor,0,0), eps=0.5
    check(p.x >= -eps && p.y >= -eps && p.x+item.width <= ancestor.width+eps
          && p.y+item.height <= ancestor.height+eps, message)
  }
  function checkGeometry() {
    var bs=buttons()
    for (var button of bs) {
      var label=labelOf(button)
      inside(label,button,"label outside button: " + label.text)
      check(!label.truncated, "truncated label: " + label.text)
      check(label.contentWidth <= label.width+0.5 && label.contentHeight <= label.height+0.5,
            "text exceeds label geometry: " + label.text)
      // The card's outer edge is insufficient: the action area clips inside it.
      for (var ancestor=button.parent; ancestor; ancestor=ancestor.parent) {
        if (ancestor.clip || ancestor === toast) {
          inside(button,ancestor,"button crosses clipping boundary: " + label.text)
          inside(label,ancestor,"label crosses clipping boundary: " + label.text)
        }
        if (ancestor === toast) break
      }
    }
    return bs
  }
  function baseRow() { return {summary:"Ready",body:"Synthetic test message"} }
  // A fixed clock, so every age label the card can show is reachable.
  readonly property double clock: new Date(2026, 0, 15, 14, 5).getTime()
  // Where the close control sat in the first case of each typography group.
  property var corners: ({})
  function closeControl() {
    var found=nodes(toast).filter(n => n.text === "\u2715" && n.rightClicked !== undefined)
    check(found.length === 1, "expected one close control")
    return found[0]
  }
  // The close control must not move with the content: not with the title's
  // length, the age label's width, an icon, marks, a count or actions.
  function checkCorner(c) {
    var shut=closeControl(), title=nodes(toast).find(n => n.text === toast.row.summary && n.lineCount !== undefined)
    check(shut.visible && shut.enabled, "close control is not reachable")
    if (c.lines) check(title.lineCount >= c.lines, "title fixture wrapped to " + title.lineCount + " lines")
    var p=shut.mapToItem(toast, 0, 0)
    var corner={right: toast.width - (p.x + shut.width), top: p.y, w: shut.width, h: shut.height}
    var group=toast.fontScale + (toast.hasBody ? ":body" : ":bare")
    var first=corners[group]
    if (!first) { corners[group]=corner; first=corner }
    check(Math.abs(corner.right-first.right) < 0.5 && Math.abs(corner.top-first.top) < 0.5,
          c.label + ": close control moved to right " + corner.right.toFixed(1) + " top " + corner.top.toFixed(1)
          + ", expected right " + first.right.toFixed(1) + " top " + first.top.toFixed(1))
    // And it sits on the title's first line, not the middle of the title.
    var t=title.mapToItem(toast, 0, 0), line=title.implicitHeight / Math.max(1, title.lineCount)
    check(Math.abs((p.y + shut.height / 2) - (t.y + line / 2)) < 1,
          c.label + ": close control is not centred on the title's first line")
    checkStackControl(c, shut, title)
  }
  // The front card of an open stack clears the whole stack from beside the
  // close control; every other card has only the close control. A shut stack
  // shows it only on a front card under the pointer.
  function checkStackControl(c, shut, title) {
    if (c.leads) {
      toast.expanded=false
      var hoveredShut=nodes(toast).find(n => n.text === "Clear all" && n.rightClicked !== undefined).visible
      toast.hovered=false
      var idleShut=nodes(toast).find(n => n.text === "Clear all" && n.rightClicked !== undefined).visible
      toast.expanded=true; toast.hovered=true
      check(hoveredShut && !idleShut, c.label + ": shut stack shows the stack control wrongly")
    }
    var found=nodes(toast).filter(n => n.text === "Clear all" && n.rightClicked !== undefined)
    check(found.length === 1, "expected one stack control")
    var clear=found[0]
    check(clear.visible === !!c.leads, c.label + ": stack control visibility is wrong")
    if (!c.leads) return
    inside(clear, toast, c.label + ": stack control crosses the card edge")
    var a=clear.mapToItem(toast, 0, 0), b=shut.mapToItem(toast, 0, 0), t=title.mapToItem(toast, 0, 0)
    check(a.x + clear.width <= b.x, c.label + ": stack control overlaps the close control")
    check(t.x + title.width <= a.x, c.label + ": stack control overlaps the title")
    var label=nodes(clear).find(n => n !== clear && n.text === "Clear all" && n.lineCount !== undefined)
    check(label && label.contentWidth <= clear.width + 0.5, c.label + ": stack control label is clipped")
    var before=stackDismissals
    clear.clicked()
    check(stackDismissals === before + 1, c.label + ": stack control does not dismiss the stack")
  }
  function configure(c) {
    toast.deedsOpen=false; toast.menuOpen=false; toast.replying=false; toast.takenKind=""
    toast.fontScale=c.scale; toast.actionsAlign=c.align || "right"
    toast.actions=[]
    toast.place=({front: true, count: c.count || 1, leads: c.leads || 1, z: 1})
    toast.now=clock
    var row=baseRow()
    if (c.kind === "visibility")
      row.body = "This notification wraps onto several lines so hiding an inactive output must not collapse the content measurement used by the visible card."
    if (c.kind === "three") {
      row.code="123456"; row.codes="123456"; row.link="https://example.com"; row.replyPath="fake:0"
    } else if (c.kind === "long") {
      toast.actions=[{id:"long",text:c.label},{id:"second",text:"Second action"}]
    } else if (c.kind === "title") {
      row.summary=c.title
    } else if (c.kind === "corner") {
      row.summary=c.title
      if (c.bare) delete row.body
      row.ts=(clock - (c.age || 0) * 1000) / 1000
      if (c.marks) { row.code="123456"; row.codes="123456"; row.link="https://example.com" }
      if (c.icon) row.stored_image=String(Qt.resolvedUrl("Plugin/preview.png"))
      if (c.actions) toast.actions=[{id:"one",text:"Mark as read"},{id:"two",text:"Archive"}]
    }
    toast.row=row
  }
  function next() {
    index++
    if (index === cases.length) {
      console.log("PASS",profile,cases.length,"cases: row/list geometry, activation, replacements and titles")
      Qt.quit(); return
    }
    configure(cases[index]); phase="row"
  }
  Component.onCompleted: {
    // Explicit typography makes the check independent of the user's current theme.
    Style.fontBaseSize=profile === "large" ? 14 : 12
    Style.fontFamily=profile === "proportional" ? "sans-serif" : "monospace"
    Style.fontOverrides={}; Style.spacingOverrides={}; Style.styleOverrides={}
    Style.spacingScale=1; Style.spacingScaleWithFont=true
    var out=[{kind:"visibility",scale:1}]
    for (var percent=75; percent<=200; percent+=5)
      for (var align of ["left","right"])
        out.push({kind:"three",scale:percent/100,align:align})
    for (var label of ["A much longer action label",
                       "A very long action label that must wrap across several lines inside the notification card",
                       "AnUnbrokenActionIdentifierThatMustWrapWithoutLosingAnyCharacters",
                       "إجراء طويل لاختبار التفاف النص داخل زر الإشعار",
                       "<b>Literal action label</b>"])
      for (var scale of [0.75,1,2]) out.push({kind:"long",scale:scale,label:label})
    for (var size of [0.75,1,1.25,1.5,2]) {
      out.push({kind:"title",scale:size,title:"Ready",wrap:false})
      out.push({kind:"title",scale:size,title:"Workspace layout set to scrolling and ready for the next application window",wrap:true})
    }
    var long="A much longer notification title that keeps going so that it has to wrap onto a second and then a third line"
    var longer=long + ", and then keeps on going for long enough to need more lines than the card shows while it is closed"
    for (var cornerScale of [1,1.5])
      for (var bare of [false,true])
        for (var shape of [{label:"short title",title:"Ready"},
                           {label:"three-line title",title:long,lines:3},
                           {label:"open long title",title:longer,lines:4},
                           {label:"age 5m",title:"Ready",age:300},
                           {label:"age 14:05",title:"Ready",age:3*3600},
                           {label:"age yesterday",title:"Ready",age:26*3600},
                           {label:"icon",title:"Ready",icon:true},
                           {label:"marks",title:"Ready",marks:true},
                           {label:"stack count",title:"Ready",count:3},
                           {label:"stack lead",title:"Ready",leads:3},
                           {label:"stack lead, long title",title:long,leads:3,lines:3},
                           {label:"actions",title:long,actions:true}])
          out.push(Object.assign({kind:"corner",scale:cornerScale,bare:bare}, shape))
    cases=out
  }
  Timer {
    interval: 180; running: true; repeat: true
    onTriggered: {
      try {
        if (test.phase === "start") { test.next(); return }
        var c=test.cases[test.index], bs=test.checkGeometry()
        var title=test.nodes(toast).find(n=>n.text===toast.row.summary && n.lineCount !== undefined)
        if (c.kind === "corner") { test.checkCorner(c); test.next(); return }
        test.check(title && !title.truncated,"title unexpectedly truncated")
        if (c.kind === "visibility") {
          if (test.phase === "row") {
            test.visibleCardHeight = toast.targetHeight
            toast.visible = false
            test.phase = "hidden"
            return
          }
          test.check(Math.abs(toast.targetHeight - test.visibleCardHeight) < 0.5,
                     "hiding an output changed the card's measured height")
          if (test.phase === "hidden") {
            toast.visible = true
            test.phase = "visible"
            return
          }
          test.next(); return
        }
        if (c.kind === "title") {
          titleMeasure.font = title.font
          // Build a genuinely overflowing fixture under the current font metrics.
          // A naturally fitting summary must remain a valid single-line title.
          if (c.wrap && titleMeasure.advanceWidth <= title.width) {
            toast.row={summary:toast.row.summary + " and another workspace",body:"Synthetic test message"}
            return
          }
          test.check(c.wrap ? title.lineCount>1 : title.lineCount===1,"incorrect wrapping for title fixture")
          test.check(bs.length===0,"unexpected actions on title fixture")
          test.next(); return
        }
        if (test.phase === "row") {
          test.check(bs.length>0,"no reachable actions")
          var more=bs.find(b=>b.deed.kind==="more")
          test.check(!!more===toast.overflows,"More visibility does not match overflow")
          if (more) {
            more.clicked(); test.phase="list"; return
          }
          test.check(bs.length===toast.allDeeds.length,"missing row actions")
          // Also exercise full-width labels when the current row happens to fit.
          toast.doDeed({kind:"more"}); test.phase="list"; return
        }
        if (test.phase === "list") {
          test.check(bs.length===toast.allDeeds.length && bs.every(b=>b.wide),"More must expose every action")
          if (c.kind === "long" && toast.fontScale < 2) {
            toast.fontScale=2; test.phase="resized"; return
          }
        }
        if (test.phase === "list" || test.phase === "resized") {
          if (c.kind === "three") {
            var replies=test.requestedReplies
            bs.find(b=>b.deed.kind==="reply").clicked()
            test.check(test.requestedReplies===replies+1,"Reply is not reachable through More")
          } else {
            test.invokedAction=""
            bs.find(b=>b.deed.value==="long").clicked()
            test.check(test.invokedAction==="long","wrapped action does not activate")
          }
          // Replace actions on the same card while its list is open.
          toast.row=test.baseRow(); toast.actions=[{id:"replacement",text:"Replacement action"}]
          test.phase="replacement"; return
        }
        test.check(bs.length===1 && bs[0].deed.value==="replacement","stale actions after replacement")
        test.next()
      } catch(e) { console.error("FAIL",e); Qt.exit(1) }
    }
  }
}
