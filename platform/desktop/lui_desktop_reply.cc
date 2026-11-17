#include "lui_desktop_reply.hh"
#include <map>
#include <mutex>

extern "C" {
#include <caml/mlvalues.h>
#include <caml/memory.h>
}

namespace {
std::mutex sinks_mutex;
std::map<int, std::shared_ptr<LuiReplySink>> sinks;
int next_session = 0;
}

std::shared_ptr<LuiReplySink> lui_register_reply_sink(
    std::function<void(std::function<void()>)> dispatch,
    std::function<void(const std::string &, const std::string &)> deliver) {
  auto sink = std::make_shared<LuiReplySink>();
  std::lock_guard<std::mutex> lock(sinks_mutex);
  sink->session = ++next_session;
  sink->dispatch = std::move(dispatch);
  sink->deliver = std::move(deliver);
  sinks.emplace(sink->session, sink);
  return sink;
}

void lui_retire_reply_sink(const std::shared_ptr<LuiReplySink> &sink) {
  if (!sink) return;
  std::lock_guard<std::mutex> lock(sinks_mutex);
  sink->active = false;
  sinks.erase(sink->session);
}

bool lui_post_reply(int session, int epoch, const std::string &id, const std::string &body) {
  std::lock_guard<std::mutex> lock(sinks_mutex);
  auto found = sinks.find(session);
  if (found == sinks.end()) return false;
  auto sink = found->second;
  // Dispatch while retirement is excluded; the platform object is still live.
  sink->dispatch([sink, epoch, id, body] {
    if (sink->active && sink->epoch == epoch) sink->deliver(id, body);
  });
  return true;
}

std::string lui_json_string(const std::string &value) {
  std::string output = "\"";
  static const char hex[] = "0123456789abcdef";
  for (unsigned char character : value) {
    if (character == '"' || character == '\\') {
      output += '\\'; output += character;
    } else if (character < 32) {
      output += "\\u00"; output += hex[character >> 4]; output += hex[character & 15];
    } else output += character;
  }
  output += '"';
  return output;
}

extern "C" CAMLprim value lui_desktop_reply(value reply) {
  CAMLparam1(reply);
  const int session = Int_val(Field(reply, 0)), epoch = Int_val(Field(reply, 1));
  const std::string id(String_val(Field(reply, 2)), caml_string_length(Field(reply, 2)));
  const std::string body(String_val(Field(reply, 3)), caml_string_length(Field(reply, 3)));
  lui_post_reply(session, epoch, id, body);
  CAMLreturn(Val_unit);
}
