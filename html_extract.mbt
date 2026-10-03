// J9 HTML 面（JSON-LD 1.1 API REC 9.5——HTML script 提取）：
// Process HTML（9.5.1）+ Extract Script Content（9.5.2）两算法落码。
// 扫描器 = 最小良构 HTML 状态机：只认 <script … type=application/ld+json>
// 开标与 </script 闭标（ASCII 大小写不敏感）；textContent 原文直通
// （script 是 raw text 元素——e010 oracle：&lt;&amp;&gt; 不解码实体）。
// 50 例勘定：无双转义嵌套（<!-- 区内 <script>）建模需求；EOF 截断按
// HTML 规则视作元素闭合。

///|
/// 一枚 JSON-LD script 元素（文档序）：id 属性词面 + textContent 原文
priv struct HtmlScript {
  id_attr : String?
  content : String
}

///|
/// 扫描状态（最小良构形——注释/标注/标签/属性/script 原文）
priv enum HtmlScanMode {
  HtmlText // 标签外
  HtmlTagStart // '<' 后首字符分派
  HtmlBangDecl // <! …（含 <!-- 前缀探测，dash 计数）
  HtmlComment // <!-- → -->
  HtmlStartTag // 标签名段
  HtmlTagBody // 属性段
  HtmlAttrValueStart // '=' 后首字符（引号探测）
  HtmlAttrQuoted // 引号值内
  HtmlAttrBare // 裸值
  HtmlEndTag // </ 名称段（非 script 语境）
  HtmlScriptRaw // script 原文内
  HtmlScriptLt // script 原文内 '<' 候选（</script 探测）
  HtmlScriptEndProbe // '</script' 已满 → 下一字符定终止
  HtmlEndSkip // </script 已闭 → 跳至 >
}

///|
/// script 原文语境判定（EOF 收口用；平铺等值——避 is 或模式的 fmt 括号坑）
fn html_in_script(mode : HtmlScanMode) -> Bool {
  mode is HtmlScriptRaw || mode is HtmlScriptLt || mode is HtmlScriptEndProbe
}

///|
/// ASCII 大小写不敏感等值（标签名/type 属性比较口径）
fn html_ci_equals(first : String, second : String) -> Bool {
  if first.length() != second.length() {
    return false
  }
  for i in 0..<first.length() {
    let a = first[i].to_int()
    let b = second[i].to_int()
    let fa = if a >= 65 && a <= 90 { a + 32 } else { a }
    let fb = if b >= 65 && b <= 90 { b + 32 } else { b }
    if fa != fb {
      return false
    }
  }
  true
}

///|
/// `</script` 前缀探测（ASCII 大小写不敏感；text 长出 target = 假）
fn html_ci_prefix_of(target : String, text : String) -> Bool {
  if text.length() > target.length() {
    return false
  }
  for i in 0..<text.length() {
    let a = target[i].to_int()
    let b = text[i].to_int()
    let fa = if a >= 65 && a <= 90 { a + 32 } else { a }
    let fb = if b >= 65 && b <= 90 { b + 32 } else { b }
    if fa != fb {
      return false
    }
  }
  true
}

///|
const HTML_LD_JSON_TYPE : String = "application/ld+json"

///|
/// HTML 空白（标签/属性分隔口径）
fn html_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

///|
/// 扫描器状态束（单遍状态机；段切换即换新累计器）
priv struct HtmlScanner {
  mut mode : HtmlScanMode
  mut tag_name : StringBuilder
  mut attr_name : StringBuilder
  mut attr_value : StringBuilder
  mut script_type : String?
  mut script_id : String?
  mut capture : Bool
  mut content : StringBuilder
  mut candidate : StringBuilder
  mut quote : Char
  mut comment_dashes : Int
  mut prev1 : Char
  mut prev2 : Char
  mut base_attr : String? // <base href> 属性暂存（te020——HTML 文档基）
  mut base_href : String? // 首个 <base href> 词面（HTML 规则首现生效）
  scripts : Array[HtmlScript]
}

///|
/// 扫描产物：JSON-LD script 集合 + 文档基 href 词面
priv struct HtmlScanResult {
  scripts : Array[HtmlScript]
  base_href : String?
}

///|
/// 收集文档序全部 JSON-LD script 元素（REC 9.5：JSON-LD script = type 属性
/// 为 application/ld+json 的 script 元素；textContent = 开闭标之间原文）
fn html_ld_scripts(html : String) -> HtmlScanResult {
  let scanner = HtmlScanner::{
    mode: HtmlText,
    tag_name: StringBuilder(),
    attr_name: StringBuilder(),
    attr_value: StringBuilder(),
    script_type: None,
    script_id: None,
    capture: false,
    content: StringBuilder(),
    candidate: StringBuilder(),
    quote: '"',
    comment_dashes: 0,
    prev1: ' ',
    prev2: ' ',
    base_attr: None,
    base_href: None,
    scripts: [],
  }
  for ch in html {
    scanner.step(ch)
  }
  // EOF 截断（HTML 规则：script 内 EOF 视作闭合）
  if html_in_script(scanner.mode) && scanner.capture {
    scanner.emit_script()
  }
  HtmlScanResult::{ scripts: scanner.scripts, base_href: scanner.base_href, }
}

///|
fn HtmlScanner::step(self : HtmlScanner, ch : Char) -> Unit {
  match self.mode {
    HtmlText => if ch == '<' { self.mode = HtmlTagStart } else { () }
    HtmlTagStart => {
      // '<' 后首字符分派
      let code = ch.to_int()
      if (code >= 97 && code <= 122) || (code >= 65 && code <= 90) {
        self.tag_name = StringBuilder()
        self.tag_name.write_char(ch)
        self.mode = HtmlStartTag
      } else if ch == '!' || ch == '?' {
        self.comment_dashes = 0
        self.mode = HtmlBangDecl
      } else if ch == '/' {
        self.mode = HtmlEndTag
      } else {
        // 残字符（如 '< 5'）回文本
        self.mode = HtmlText
      }
    }
    HtmlBangDecl =>
      if ch == '-' {
        self.comment_dashes = self.comment_dashes + 1
        if self.comment_dashes == 2 {
          self.mode = HtmlComment
        }
      } else {
        self.comment_dashes = 0
        if ch == '>' {
          self.mode = HtmlText
        }
      }
    HtmlComment => {
      if ch == '>' && self.prev1 == '-' && self.prev2 == '-' {
        self.mode = HtmlText
      }
      self.prev2 = self.prev1
      self.prev1 = ch
    }
    HtmlStartTag => {
      let code = ch.to_int()
      if ch == '>' {
        self.close_start_tag()
      } else if html_is_space(ch) || ch == '/' {
        self.mode = HtmlTagBody
      } else if (code >= 97 && code <= 122) || (code >= 65 && code <= 90) {
        self.tag_name.write_char(ch)
      } else {
        ()
      }
    }
    HtmlTagBody =>
      if ch == '>' {
        self.finalize_attr()
        self.close_start_tag()
      } else if html_is_space(ch) || ch == '/' {
        self.finalize_attr()
      } else if ch == '=' {
        self.mode = HtmlAttrValueStart
      } else {
        self.attr_name.write_char(ch)
      }
    HtmlAttrValueStart =>
      if ch == '"' || ch == '\'' {
        self.attr_value = StringBuilder()
        self.quote = ch
        self.mode = HtmlAttrQuoted
      } else if ch == '>' {
        // 空值属性（type= → 非法媒体类型，非 ld+json）
        self.finalize_attr()
        self.close_start_tag()
      } else if html_is_space(ch) || ch == '/' {
        self.finalize_attr()
        self.mode = HtmlTagBody
      } else {
        self.attr_value = StringBuilder()
        self.attr_value.write_char(ch)
        self.mode = HtmlAttrBare
      }
    HtmlAttrQuoted =>
      if ch == self.quote {
        self.finalize_attr()
        self.mode = HtmlTagBody
      } else {
        self.attr_value.write_char(ch)
      }
    HtmlAttrBare =>
      if ch == '>' {
        self.finalize_attr()
        self.close_start_tag()
      } else if html_is_space(ch) || ch == '/' {
        self.finalize_attr()
        self.mode = HtmlTagBody
      } else {
        self.attr_value.write_char(ch)
      }
    HtmlEndTag => if ch == '>' { self.mode = HtmlText } else { () }
    HtmlScriptRaw =>
      if ch == '<' {
        self.candidate = StringBuilder()
        self.candidate.write_char('<')
        self.mode = HtmlScriptLt
      } else if self.capture {
        self.content.write_char(ch)
      } else {
        ()
      }
    HtmlScriptLt => {
      self.candidate.write_char(ch)
      let text = self.candidate.to_string()
      if html_ci_prefix_of("</script", text) {
        if text.length() == 8 {
          self.mode = HtmlScriptEndProbe
        } else {
          ()
        }
      } else {
        // 候选破裂 → 整段回填原文（注：候选尾恰为 '<' 的极端序列不重探
        // ——50 例勘定无此形）
        if self.capture {
          self.content.write_string(text)
        }
        self.mode = HtmlScriptRaw
      }
    }
    HtmlScriptEndProbe =>
      if ch == '>' {
        self.emit_script()
        self.mode = HtmlText
      } else if html_is_space(ch) || ch == '/' {
        self.emit_script()
        self.mode = HtmlEndSkip
      } else {
        // 非终止符（如 </scriptx）→ 候选回填，续读原文
        if self.capture {
          self.content.write_string(self.candidate.to_string())
          self.content.write_char(ch)
        }
        self.mode = HtmlScriptRaw
      }
    HtmlEndSkip => if ch == '>' { self.mode = HtmlText } else { () }
  }
}

///|
/// 属性收口：name=value 落位（script 的 type/id 判定）
fn HtmlScanner::finalize_attr(self : HtmlScanner) -> Unit {
  let name = self.attr_name.to_string()
  if name.length() == 0 {
    return
  }
  let value = self.attr_value.to_string()
  if html_ci_equals(name, "type") {
    self.script_type = Some(value)
  } else if html_ci_equals(name, "id") {
    self.script_id = Some(value)
  } else if html_ci_equals(self.tag_name.to_string(), "base") &&
    html_ci_equals(name, "href") {
    self.base_attr = Some(value)
  } else {
    ()
  }
  self.attr_name = StringBuilder()
  self.attr_value = StringBuilder()
}

///|
/// start tag 收口：script 判定字段落位，转入原文/文本态
fn HtmlScanner::close_start_tag(self : HtmlScanner) -> Unit {
  let name = self.tag_name.to_string()
  if html_ci_equals(name, "script") {
    match self.script_type {
      Some(media_type) =>
        self.capture = html_ci_equals(media_type, HTML_LD_JSON_TYPE)
      None => self.capture = false
    }
    if self.capture {
      self.content = StringBuilder()
    }
    self.mode = HtmlScriptRaw
    if !self.capture {
      // 非 ld+json script：判定字段即弃（capture 件留待 emit 重置——
      // id 属性要存活到落账）
      self.script_type = None
      self.script_id = None
    }
  } else {
    self.capture = false
    self.mode = HtmlText
    self.script_type = None
    self.script_id = None
    // <base href>（HTML 文档基——te020 oracle；首现生效）
    if html_ci_equals(name, "base") {
      match self.base_attr {
        Some(href) =>
          if self.base_href is None {
            self.base_href = Some(href)
          } else {
            ()
          }
        None => ()
      }
    }
    self.base_attr = None
  }
  self.tag_name = StringBuilder()
  self.attr_name = StringBuilder()
  self.attr_value = StringBuilder()
}

///|
/// script 元素落账（仅 capture 件）
fn HtmlScanner::emit_script(self : HtmlScanner) -> Unit {
  if self.capture {
    self.scripts.push(HtmlScript::{
      id_attr: self.script_id,
      content: self.content.to_string(),
    })
  }
  self.capture = false
  self.content = StringBuilder()
  self.script_type = None
  self.script_id = None
}

///|
/// percent 解码（REC 9.5.1 fragment 分支——id 匹配前解码 %XX 序列）
fn html_percent_decode(input : String) -> String {
  // 索引式（迭代器无回退——'%' 破形时两 consume 位会吞尾字符，wbtest 实证）
  let chars : Array[Char] = []
  for ch in input {
    chars.push(ch)
  }
  let bytes : Array[Byte] = []
  let mut i = 0
  while i < chars.length() {
    let code = chars[i].to_int()
    if code == 37 && i + 2 < chars.length() {
      match (html_hex_nibble(chars[i + 1]), html_hex_nibble(chars[i + 2])) {
        (Some(h), Some(l)) => {
          bytes.push((h * 16 + l).to_byte())
          i = i + 3
        }
        _ => {
          // 破形 → '%' 按字面
          bytes.push((37 : Int).to_byte())
          i = i + 1
        }
      }
    } else if code == 37 {
      bytes.push((37 : Int).to_byte())
      i = i + 1
    } else if code < 128 {
      bytes.push(code.to_byte())
      i = i + 1
    } else {
      // 非 ASCII 标量 → 按其 UTF-8 字节展开
      for unit_byte in @utf8.encode(chars[i].to_string()) {
        bytes.push(unit_byte)
      }
      i = i + 1
    }
  }
  @utf8.decode_lossy(Bytes::from_array(bytes))
}

///|
/// hex 位 → 0-15
fn html_hex_nibble(ch : Char) -> Int? {
  let code = ch.to_int()
  if code >= 48 && code <= 57 {
    Some(code - 48)
  } else if code >= 97 && code <= 102 {
    Some(code - 87)
  } else if code >= 65 && code <= 70 {
    Some(code - 55)
  } else {
    None
  }
}

///|
/// REC 9.5.2 Extract Script Content：source 非法 JSON → invalid script element
fn html_validate_script(
  script : HtmlScript,
  document_base : String?,
) -> Result[HtmlScriptSource, JsonLdError] {
  match parse_json(script.content) {
    Ok(_) =>
      Ok(HtmlScriptSource::{
        source: script.content,
        document_base,
        no_scripts: false,
      })
    Err(_) => Err(InvalidScriptElement("script content is not valid JSON"))
  }
}

///|
/// REC 9.5.1 Process HTML——script 源选择 + 逐 script JSON 校验。
/// fragment = 输入 URL `#` 后段（调用方剥离，percent 解码在此）；
/// extract_all = extractAllScripts 选项。返回 = 喂下游文档函数的 JSON 源
/// 文本：单件/fragment 返回 textContent 原文（零变换保真）；extract_all
/// 返回合并数组重文（数组并尾/标量追加——REC 9.5.1 末支；下游重解析）。
pub struct HtmlScriptSource {
  /// 喂下游文档函数的 JSON 源文本
  source : String
  /// HTML 文档基（首个 <base href> 已对 document_url 相对解析的绝对形；
  /// 无 <base> = None——documentUrl 本身即文档基）
  document_base : String?
  /// **无 JSON-LD script 且 extractAllScripts=false**（REC 9.5.1 无 script 臂）。
  /// 套件 oracle 在此**通道分叉**（同形异判，2026-10-03 勘定）：ExpandTest #te006
  /// ⇒ loading document failed；**ToRDFTest #tr006 ⇒ 空数据集**。抽取器只报事实
  /// （本旗 + source="[]"），通道语义由套件 harness 裁定。
  no_scripts : Bool
}

///|
/// REC 9.5.1 Process HTML——script 源选择 + 逐 script JSON 校验 + 文档基。
/// document_url = REC url 参数（检索 URL：option.base ?? 文档位置，调用方
/// 剥 fragment）；fragment = 输入 URL `#` 后段；extract_all = extractAllScripts
/// 选项。返回见 HtmlScriptSource：单件/fragment 返回 textContent 原文
/// （零变换保真）；extract_all 返回合并数组重文（数组并尾/标量追加——
/// REC 9.5.1 末支；下游重解析）。
pub fn html_script_source(
  html : String,
  document_url : String?,
  fragment : String?,
  extract_all : Bool,
) -> Result[HtmlScriptSource, JsonLdError] {
  let scan = html_ld_scripts(html)
  let scripts = scan.scripts
  // REC 9.5.1 首步：documentUrl = HTML Document Base URL（<base href> 对
  // documentUrl 解析；无 <base> = documentUrl 本身——返回 None 由调用方取
  // 检索 URL）
  let document_base : String? = match scan.base_href {
    Some(href) => Some(resolve_base_value(href, document_url))
    None => None
  }
  match fragment {
    Some(raw) => {
      // REC：按 id 定 script（percent 解码后）；未命中 → loading document failed
      // （扫描器只收 JSON-LD script，故未命中兼涵「非 JSON-LD script 元素」臂）
      let wanted = html_percent_decode(raw)
      let mut found : HtmlScript? = None
      for script in scripts {
        match script.id_attr {
          Some(id) => if id == wanted { found = Some(script) } else { () }
          None => ()
        }
      }
      match found {
        None =>
          Err(
            LoadingDocumentFailed(
              "fragment #\{wanted}: no JSON-LD script element",
            ),
          )
        Some(script) => html_validate_script(script, document_base)
      }
    }
    None =>
      if extract_all {
        let parts : Array[JsonValue] = []
        for script in scripts {
          match parse_json(script.content) {
            Ok(JsonValue::Array(items)) =>
              for item in items {
                parts.push(item)
              }
            Ok(value) => parts.push(value)
            Err(_) =>
              return Err(
                InvalidScriptElement("script content is not valid JSON"),
              )
          }
        }
        Ok(HtmlScriptSource::{
          source: jv_render(JsonValue::Array(parts)),
          document_base,
          // extractAllScripts=true 时空抽取是**正常空结果**（#te007 正例
          // "expands as empty"）⇒ 不置无 script 旗（该旗专表 #te006 臂）
          no_scripts: false,
        })
      } else {
        match scripts.get(0) {
          None =>
            // 无 script 臂：报事实（旗 + 空数组源），通道语义交 harness 裁定
            // （#te006 expand ⇒ error / #tr006 toRdf ⇒ 空数据集；见字段注释）
            Ok(HtmlScriptSource::{
              source: "[]",
              document_base,
              no_scripts: true,
            })
          Some(script) => html_validate_script(script, document_base)
        }
      }
  }
}
