// ===== jsonld 命令行薄壳（入口 + 走参）=====
// 库面算法直出；本壳不接网络（remote-doc 圈外），上下文一律本地文件。
// 用法：moon run cmd/main -- <command> [options] <inputs>

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage(false)
    return
  }
  let argv = args[1:]
  match parse_invocation(argv) {
    Some(invocation) => dispatch(invocation)
    None => () // 解析期已输出 usage / 错误
  }
}

///|
struct CliInvocation {
  mut verb : String
  positionals : Array[String]
  mut base : String?
  mut mode_1_0 : Bool
  mut hash_sha384 : Bool
}

///|
/// argv 走参：首词 = 动词；其后 --base/--mode/--hash 选项 + 位置输入。
/// 返回 None = 解析期已输出 usage / 错误（main 直接收工）。
fn parse_invocation(argv : ArrayView[String]) -> CliInvocation? {
  let invocation = CliInvocation::{
    verb: "",
    positionals: [],
    base: None,
    mode_1_0: false,
    hash_sha384: false,
  }
  let mut verb_seen = false
  let mut index = 0
  let length = argv.length()
  while index < length {
    let arg = argv[index]
    if !verb_seen {
      invocation.verb = arg
      verb_seen = true
      index = index + 1
      continue
    }
    if arg == "--base" {
      if index + 1 >= length {
        eprintln("jsonld：--base 缺值")
        return None
      }
      invocation.base = Some(argv[index + 1])
      index = index + 2
    } else if arg == "--mode" {
      if index + 1 >= length {
        eprintln("jsonld：--mode 缺值")
        return None
      }
      let mode = argv[index + 1]
      if mode == "1.0" {
        invocation.mode_1_0 = true
      } else if mode != "1.1" {
        eprintln("jsonld：--mode 只认 1.0 / 1.1，得到 \{mode}")
        return None
      }
      index = index + 2
    } else if arg == "--hash" {
      if index + 1 >= length {
        eprintln("jsonld：--hash 缺值")
        return None
      }
      let hash = argv[index + 1]
      if hash == "sha384" {
        invocation.hash_sha384 = true
      } else if hash != "sha256" {
        eprintln("jsonld：--hash 只认 sha256 / sha384，得到 \{hash}")
        return None
      }
      index = index + 2
    } else if arg == "-h" || arg == "--help" {
      print_usage(false)
      return None
    } else if arg.has_prefix("--") {
      eprintln("jsonld：未知选项 \{arg}")
      print_usage(true)
      return None
    } else {
      invocation.positionals.push(arg)
      index = index + 1
    }
  }
  // 无参 = 用法展示（exit 0）
  if !verb_seen {
    print_usage(false)
    return None
  }
  Some(invocation)
}

///|
/// 用法文本：err=true 走 stderr（错误路径），否则 stdout（--help / 无参）。
fn print_usage(err : Bool) -> Unit {
  let emit = fn(text : String) -> Unit {
    if err {
      eprintln(text)
    } else {
      println(text)
    }
  }
  emit("jsonld——JSON-LD 1.1 / RDFC-1.0 命令行薄壳")
  emit("用法：moon run cmd/main -- <command> [options] <inputs>")
  emit("commands:")
  emit("  expand <doc>                展开文档")
  emit(
    "  compact <doc> <context>     压缩（context 为上下文文档文件）",
  )
  emit("  flatten <doc> [context]     展平（context 可选）")
  emit("  frame <doc> <frame>         帧")
  emit("  to-rdf <doc>                JSON-LD → N-Quads（逐行）")
  emit("  from-rdf <nq>               N-Quads → JSON-LD 节点对象")
  emit(
    "  canonicalize <nq>           RDFC-1.0 规范化（输出规范数据集）",
  )
  emit("  json-canonical <json>       JCS（RFC 8785）规范化 JSON")
  emit("options:")
  emit("  --base <iri>                文档 base IRI")
  emit("  --mode <1.0|1.1>            processing mode（默认 1.1）")
  emit(
    "  --hash <sha256|sha384>      canonicalize 哈希档（默认 sha256）",
  )
}
