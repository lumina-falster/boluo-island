# -*- coding: utf-8 -*-
"""菠萝岛果实成熟提醒：读取 data.json，检查即将成熟/已成熟的果实，推送提醒并回写标记。
仅使用 Python 标准库，在 GitHub Actions 的 checkout 仓库根目录下运行。"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

TZ = timezone(timedelta(hours=8))
DATA_FILE = "data.json"


def load_data():
    with open(DATA_FILE, encoding="utf-8") as f:
        return json.load(f)


def fmt_dt(dt):
    return dt.strftime("%m-%d %H:%M")


def parse_ms(ms):
    return datetime.fromtimestamp(ms / 1000, TZ)


def http_post(url, payload, form=False, timeout=15):
    if form:
        data = urllib.parse.urlencode(payload).encode("utf-8")
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
    else:
        data = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def send_serverchan(key, title, md):
    try:
        res = http_post("https://sctapi.ftqq.com/%s.send" % key,
                        {"title": title, "desp": md}, form=True)
        ok = res.get("code") == 0
        print("Server酱:", res.get("message", res))
        return ok
    except Exception as e:
        print("Server酱发送失败:", e)
        return False


def send_wecom(hook, md):
    try:
        res = http_post(hook, {"msgtype": "markdown", "markdown": {"content": md}})
        ok = res.get("errcode") == 0
        print("企业微信:", res.get("errmsg", res))
        return ok
    except Exception as e:
        print("企业微信发送失败:", e)
        return False


def send_pushplus(token, title, md):
    try:
        res = http_post("https://www.pushplus.plus/send",
                        {"token": token, "title": title, "content": md, "template": "markdown"})
        ok = res.get("code") == 200
        print("PushPlus:", res.get("msg", res))
        return ok
    except Exception as e:
        print("PushPlus发送失败:", e)
        return False


def git(*args, check=True):
    return subprocess.run(["git", *args], check=check)


def commit_if_changed():
    if subprocess.run(["git", "diff", "--quiet", "--", DATA_FILE]).returncode == 0:
        return
    git("add", DATA_FILE)
    git("-c", "user.name=boluo-bot",
        "-c", "user.email=bot@users.noreply.github.com",
        "commit", "-m", "chore: 更新提醒标记")
    if git("push", check=False).returncode != 0:
        git("pull", "--rebase", "--autostash")
        git("push")


def main():
    test = os.environ.get("TEST_MODE", "false").lower() == "true"
    data = load_data()
    settings = data.get("settings", {})
    channels = settings.get("channels", {})
    remind = settings.get("remindMinutes", 15) or 0
    notify_ripe = settings.get("notifyOnRipe", True)

    now = datetime.now(TZ)
    soon, ripe = [], []
    changed = False
    for p in data.get("plots", []):
        if not p.get("ripenAt"):
            continue
        ripen = parse_ms(p["ripenAt"])
        if now >= ripen:
            if test:
                ripe.append((p, ripen))
            elif notify_ripe and not p.get("notifiedRipe"):
                p["notifiedRipe"] = True
                changed = True
                ripe.append((p, ripen))
        elif now >= ripen - timedelta(minutes=remind):
            if test:
                soon.append((p, ripen))
            elif not p.get("notifiedSoon"):
                p["notifiedSoon"] = True
                changed = True
                soon.append((p, ripen))

    total = sum(1 for p in data.get("plots", []) if p.get("ripenAt"))

    if test:
        title = "🍍 菠萝岛助手·测试通知"
        lines = ["通道配置成功，这是一条测试消息。", "", "当前共 **%d** 块地在倒计时。" % total]
    else:
        parts = []
        if soon:
            parts.append("**即将成熟（%d分钟内）**" % remind if remind else "**即将成熟**")
            for p, rt in soon:
                mins = max(0, int((rt - now).total_seconds() // 60))
                fert = p.get("fertilizer") or ""
                fert = "（%s）" % fert if fert and fert != "无" else ""
                extra = "\n> 备注：%s" % p["note"] if p.get("note") else ""
                parts.append("- %s %s%s：约 **%d分钟**后成熟（%s）%s"
                             % (p["name"], p.get("fruit", ""), fert, mins, fmt_dt(rt), extra))
        if ripe:
            parts.append("**已成熟，快去收获！**")
            for p, rt in ripe:
                parts.append("- %s %s：已于 %s 成熟" % (p["name"], p.get("fruit", ""), fmt_dt(rt)))
        if not parts:
            print("暂无需要提醒的内容（%d 块地在倒计时）" % total)
            return
        n = len(soon) + len(ripe)
        title = "🍍 菠萝岛成熟提醒" + ("（%d条）" % n if n > 1 else "")
        lines = parts

    md = "\n".join(lines)
    results = []

    if channels.get("serverchan", True):
        key = os.environ.get("SERVERCHAN_SENDKEY", "")
        if key:
            results.append(("Server酱", send_serverchan(key, title, md)))
        else:
            print("未配置 secret SERVERCHAN_SENDKEY，跳过 Server酱")
    if channels.get("wecom", True):
        hook = os.environ.get("WECOM_WEBHOOK", "")
        if hook:
            results.append(("企业微信", send_wecom(hook, md)))
        else:
            print("未配置 secret WECOM_WEBHOOK，跳过企业微信")
    if channels.get("pushplus", False):
        token = os.environ.get("PUSHPLUS_TOKEN", "")
        if token:
            results.append(("PushPlus", send_pushplus(token, title, md)))
        else:
            print("未配置 secret PUSHPLUS_TOKEN，跳过 PushPlus")

    if not results:
        print("没有可用的通知通道（检查 settings.channels 与仓库 secrets）")
        if not test:
            sys.exit(1)
        return

    ok = [n for n, r in results if r]
    fail = [n for n, r in results if not r]
    print("发送成功:", ok or "无", "| 失败:", fail or "无")
    if not ok:
        sys.exit(1)

    if changed and not test:
        with open(DATA_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        commit_if_changed()


if __name__ == "__main__":
    main()
