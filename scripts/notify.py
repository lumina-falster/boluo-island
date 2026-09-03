# -*- coding: utf-8 -*-
"""菠萝岛果实成熟提醒 v3：
- 岛屿广播：全岛所有地块的快熟/成熟提醒，推到仓库 Secrets 配置的渠道（Server酱/企业微信/PushPlus）
- 个人推送：每个成员可配置自己的 Server酱 SendKey 与提醒范围（只提醒自己 / 全岛 / 不提醒）
- 兼容 v2 旧数据（无 members 字段时自动按单成员岛主处理，回写保持旧格式）
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


def member_name(data, mid):
    for m in data.get("members", []):
        if m.get("id") == mid:
            return m.get("name", "")
    return ""


def plot_line(data, p, rt, now, with_owner):
    mins = max(0, int((rt - now).total_seconds() // 60))
    fert = p.get("fertilizer") or ""
    fert = "（%s）" % fert if fert and fert != "无" else ""
    owner = ""
    if with_owner:
        nm = member_name(data, p.get("owner"))
        if nm:
            owner = "[%s] " % nm
    return "- %s%s %s%s：约 **%d分钟**后成熟（%s）" % (
        owner, p["name"], p.get("fruit", ""), fert, mins, fmt_dt(rt))


def ripe_line(data, p, with_owner):
    owner = ""
    if with_owner:
        nm = member_name(data, p.get("owner"))
        if nm:
            owner = "[%s] " % nm
    return "- %s%s %s：已于 %s 成熟" % (owner, p["name"], p.get("fruit", ""), fmt_dt(parse_ms(p["ripenAt"])))


def build_message(data, soon, ripe, remind, with_owner=True):
    parts = []
    if soon:
        parts.append(("**快熟啦（%d分钟内）**" % remind) if remind else "**快熟啦**")
        for p, rt in soon:
            parts.append(plot_line(data, p, rt, datetime.now(TZ), with_owner))
            if p.get("note"):
                parts.append("> 备注：%s" % p["note"])
    if ripe:
        parts.append("**已成熟，快去收菜！**")
        for p, _ in ripe:
            parts.append(ripe_line(data, p, with_owner))
    return parts


def main():
    test = os.environ.get("TEST_MODE", "false").lower() == "true"
    data = load_data()
    settings = data.get("settings", {})
    channels = settings.get("channels", {})
    remind = settings.get("remindMinutes", 15) or 0
    notify_ripe = settings.get("notifyOnRipe", True)
    members = data.get("members") or []
    v3 = bool(members) and int(data.get("version") or 2) >= 3

    now = datetime.now(TZ)
    bc_soon, bc_ripe = [], []          # 岛屿广播事件
    personal = {}                      # member_id -> {"soon": [], "ripe": []}
    changed = False

    for p in data.get("plots", []):
        if not p.get("ripenAt"):
            continue
        ripen = parse_ms(p["ripenAt"])
        if v3:
            notified = p.get("notified") or {}
            soon_list = list(notified.get("soon") or [])
            ripe_list = list(notified.get("ripe") or [])
            # --- 岛屿广播事件 ---
            if now >= ripen:
                if test:
                    bc_ripe.append((p, ripen))
                elif notify_ripe and "bc" not in ripe_list:
                    ripe_list.append("bc")
                    changed = True
                    bc_ripe.append((p, ripen))
            elif now >= ripen - timedelta(minutes=remind):
                if test:
                    bc_soon.append((p, ripen))
                elif "bc" not in soon_list:
                    soon_list.append("bc")
                    changed = True
                    bc_soon.append((p, ripen))
            # --- 个人推送事件 ---
            for m in members:
                if m.get("notify") == "不提醒" or not m.get("nk"):
                    continue
                if m.get("notify") == "只提醒自己" and p.get("owner") != m.get("id"):
                    continue
                mremind = m.get("remindMinutes")
                mremind = remind if mremind in (None, "") else (mremind or 0)
                if now >= ripen:
                    if test:
                        continue
                    if notify_ripe and m["id"] not in ripe_list:
                        ripe_list.append(m["id"])
                        changed = True
                        personal.setdefault(m["id"], {"soon": [], "ripe": []})["ripe"].append((p, ripen))
                elif now >= ripen - timedelta(minutes=mremind):
                    if test:
                        continue
                    if m["id"] not in soon_list:
                        soon_list.append(m["id"])
                        changed = True
                        personal.setdefault(m["id"], {"soon": [], "ripe": []})["soon"].append((p, ripen))
            if not test and (soon_list or ripe_list):
                p["notified"] = {"soon": soon_list, "ripe": ripe_list}
        else:
            # v2 兼容：旧布尔标记
            if now >= ripen:
                if test:
                    bc_ripe.append((p, ripen))
                elif notify_ripe and not p.get("notifiedRipe"):
                    p["notifiedRipe"] = True
                    changed = True
                    bc_ripe.append((p, ripen))
            elif now >= ripen - timedelta(minutes=remind):
                if test:
                    bc_soon.append((p, ripen))
                elif not p.get("notifiedSoon"):
                    p["notifiedSoon"] = True
                    changed = True
                    bc_soon.append((p, ripen))

    total = sum(1 for p in data.get("plots", []) if p.get("ripenAt"))

    # ---------- 发送岛屿广播 ----------
    results = []
    lines = None
    if test:
        title = "🍍 菠萝岛助手·测试通知"
        lines = ["通道配置成功，这是一条测试消息。", "",
                 "当前共 **%d** 块地在倒计时。" % total]
    else:
        parts = build_message(data, bc_soon, bc_ripe, remind, with_owner=v3)
        if parts:
            n = len(bc_soon) + len(bc_ripe)
            title = "🍍 菠萝岛成熟提醒" + ("（%d条）" % n if n > 1 else "")
            lines = parts
        else:
            print("暂无需要广播的提醒（%d 块地在倒计时）" % total)

    if lines:
        md = "\n".join(lines)
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

    # ---------- 发送个人推送 ----------
    for mid, ev in personal.items():
        m = next((x for x in members if x.get("id") == mid), None)
        if not m or not m.get("nk"):
            continue
        mremind = m.get("remindMinutes")
        mremind = remind if mremind in (None, "") else (mremind or 0)
        parts = build_message(data, ev["soon"], ev["ripe"], mremind,
                              with_owner=(m.get("notify") != "只提醒自己"))
        if not parts:
            continue
        n = len(ev["soon"]) + len(ev["ripe"])
        if m.get("notify") == "只提醒自己":
            title = "🍍 你的果实快熟啦" + ("（%d条）" % n if n > 1 else "")
        else:
            title = "🍍 全岛果实提醒" + ("（%d条）" % n if n > 1 else "")
        print("个人推送 ->", m.get("name"))
        send_serverchan(m["nk"], title, "\n".join(parts))

    # ---------- 收尾 ----------
    if results:
        ok = [n for n, r in results if r]
        fail = [n for n, r in results if not r]
        print("广播发送成功:", ok or "无", "| 失败:", fail or "无")
        if not ok:
            sys.exit(1)
    elif lines and not personal:
        print("没有可用的通知通道（检查 settings.channels 与仓库 secrets）")
        sys.exit(1)
    elif not lines and not personal and not test:
        return

    if changed and not test:
        with open(DATA_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        commit_if_changed()


if __name__ == "__main__":
    main()
