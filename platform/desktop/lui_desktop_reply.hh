#pragma once
#include <atomic>
#include <functional>
#include <memory>
#include <string>

struct LuiReplySink {
  int session;
  std::atomic<int> epoch{1};
  std::atomic<bool> active{true};
  std::function<void(std::function<void()>)> dispatch;
  std::function<void(const std::string &, const std::string &)> deliver;
};

std::shared_ptr<LuiReplySink> lui_register_reply_sink(
    std::function<void(std::function<void()>)> dispatch,
    std::function<void(const std::string &, const std::string &)> deliver);
void lui_retire_reply_sink(const std::shared_ptr<LuiReplySink> &sink);
bool lui_post_reply(int session, int epoch, const std::string &id, const std::string &body);
std::string lui_json_string(const std::string &value);
