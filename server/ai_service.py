import json
import os
import re
from typing import Any

import httpx


DEFAULT_CATEGORIES = [
    "日用品",
    "医药",
    "清洁",
    "玩具",
    "工具",
    "食品",
    "衣物",
    "证件",
    "电子",
    "其他",
]

CATEGORY_KEYWORDS = {
    "医药": ["药", "体温", "创可贴", "口罩", "棉签", "消毒", "退热", "血压"],
    "清洁": ["洗衣", "洗洁", "清洁", "拖把", "扫把", "垃圾袋", "洁厕", "抹布"],
    "玩具": ["玩具", "积木", "汽车", "恐龙", "拼图", "画板", "球", "娃娃"],
    "工具": ["螺丝", "扳手", "钳", "锤", "电钻", "卷尺", "工具"],
    "食品": ["米", "面", "油", "盐", "糖", "牛奶", "零食", "饮料", "食品"],
    "衣物": ["衣", "裤", "袜", "鞋", "帽", "外套", "内衣"],
    "证件": ["身份证", "护照", "户口", "证书", "合同", "银行卡"],
    "电子": ["手机", "电脑", "充电", "耳机", "路由器", "相机", "硬盘", "电池"],
    "日用品": ["牙膏", "牙刷", "纸巾", "毛巾", "杯", "雨伞", "梳子", "洗发", "沐浴"],
}


def provider_config() -> dict[str, Any]:
    base_url = os.environ.get("FHM_LLM_BASE_URL", "").strip().rstrip("/")
    model = os.environ.get("FHM_LLM_MODEL", "").strip()
    vision_model = os.environ.get("FHM_VISION_MODEL", "").strip() or model
    return {
        "configured": bool(base_url and model),
        "base_url": base_url,
        "model": model,
        "vision_model": vision_model,
    }


def _json_from_text(text: str) -> dict[str, Any] | None:
    text = text.strip()
    if not text:
        return None
    try:
        value = json.loads(text)
        return value if isinstance(value, dict) else None
    except json.JSONDecodeError:
        pass

    match = re.search(r"\{.*\}", text, re.S)
    if not match:
        return None
    try:
        value = json.loads(match.group(0))
        return value if isinstance(value, dict) else None
    except json.JSONDecodeError:
        return None


def _chat(
    messages: list[dict[str, Any]],
    *,
    model: str | None = None,
    timeout: float = 35,
) -> str:
    config = provider_config()
    if not config["configured"]:
        raise RuntimeError("AI provider is not configured")

    selected_model = model or config["model"]
    if not selected_model:
        raise RuntimeError("AI model is not configured")

    response = httpx.post(
        f"{config['base_url']}/chat/completions",
        headers={"Content-Type": "application/json"},
        json={
            "model": selected_model,
            "messages": messages,
            "temperature": 0.1,
        },
        timeout=timeout,
    )
    response.raise_for_status()
    body = response.json()
    return body["choices"][0]["message"]["content"]


def classify_local(name: str, notes: str = "") -> dict[str, Any]:
    text = f"{name} {notes}".lower()
    for category, keywords in CATEGORY_KEYWORDS.items():
        if any(keyword.lower() in text for keyword in keywords):
            return {
                "category": category,
                "kind": "quantity" if category in {"日用品", "医药", "清洁", "食品"} else "single",
                "reason": "根据物品名称关键字判断",
                "source": "local",
            }
    return {
        "category": "其他",
        "kind": "single",
        "reason": "未匹配到明确分类",
        "source": "local",
    }


def classify_item(name: str, notes: str = "") -> dict[str, Any]:
    config = provider_config()
    if config["configured"]:
        prompt = (
            "你是家庭物品管理助手。请给物品分类，只返回 JSON。"
            f"可选分类：{','.join(DEFAULT_CATEGORIES)}。"
            'JSON 格式：{"category":"分类","kind":"single|quantity|group","reason":"简短理由"}。'
            f"物品名称：{name}\n备注：{notes}"
        )
        try:
            parsed = _json_from_text(
                _chat([{"role": "user", "content": prompt}], timeout=20)
            )
            if parsed:
                category = str(parsed.get("category", "其他"))
                if category not in DEFAULT_CATEGORIES:
                    category = "其他"
                kind = str(parsed.get("kind", "single"))
                if kind not in {"single", "quantity", "group"}:
                    kind = "single"
                return {
                    "category": category,
                    "kind": kind,
                    "reason": str(parsed.get("reason", "AI 分类")),
                    "source": "llm",
                }
        except Exception:
            pass
    return classify_local(name, notes)


def _inventory_lines(items: list[dict[str, Any]]) -> str:
    lines = []
    for item in items[:300]:
        name = str(item.get("name", ""))
        if not name:
            continue
        location = str(item.get("location", ""))
        quantity = item.get("quantity", 1)
        unit = str(item.get("unit", "个"))
        category = str(item.get("category", ""))
        expiry = item.get("expiry_date")
        minimum = item.get("minimum_quantity")
        lines.append(
            f"- {name} | {category} | {location} | {quantity}{unit}"
            + (f" | 最低库存{minimum}{unit}" if minimum is not None else "")
            + (f" | 到期{expiry}" if expiry else "")
        )
    return "\n".join(lines)


def ask_local(question: str, items: list[dict[str, Any]]) -> dict[str, Any]:
    q = question.strip().lower()
    if not q:
        return {"answer": "请先输入问题。", "source": "local"}

    matches = []
    for item in items:
        name = str(item.get("name", ""))
        if name and (name.lower() in q or q in name.lower()):
            matches.append(item)

    if matches:
        parts = []
        for item in matches[:8]:
            parts.append(
                f"{item.get('name')}：{item.get('location', '位置未记录')}，"
                f"数量 {item.get('quantity', 1)}{item.get('unit', '个')}"
            )
        return {"answer": "；".join(parts), "source": "local"}

    if any(word in q for word in ["快过期", "到期", "过期"]):
        expiring = [item for item in items if item.get("expiry_date")]
        if not expiring:
            return {"answer": "目前没有记录到期日的物品。", "source": "local"}
        expiring.sort(key=lambda item: str(item.get("expiry_date")))
        text = "；".join(
            f"{item.get('name')}（{item.get('expiry_date')}）"
            for item in expiring[:10]
        )
        return {"answer": f"已记录到期日的物品：{text}", "source": "local"}

    if any(word in q for word in ["缺货", "库存不足", "要买", "采购"]):
        low = []
        for item in items:
            minimum = item.get("minimum_quantity")
            quantity = item.get("quantity")
            if minimum is None or quantity is None:
                continue
            try:
                if float(quantity) <= float(minimum):
                    low.append(item)
            except (TypeError, ValueError):
                continue
        if not low:
            return {"answer": "目前没有达到最低库存线的物品。", "source": "local"}
        return {
            "answer": "建议补货：" + "、".join(str(item.get("name")) for item in low[:20]),
            "source": "local",
        }

    return {
        "answer": "我暂时没有从现有物品记录中找到直接答案。可以换成“体温计在哪里”“哪些东西快过期”“哪些需要采购”这类问题。",
        "source": "local",
    }


def ask_household(question: str, items: list[dict[str, Any]]) -> dict[str, Any]:
    config = provider_config()
    if config["configured"]:
        inventory = _inventory_lines(items)
        prompt = (
            "你是家庭物品管理助手，只根据下面的家庭库存数据回答，不要编造。"
            "如果没有记录就明确说没有记录。回答要简短、直接、中文。\n\n"
            f"家庭库存：\n{inventory}\n\n问题：{question}"
        )
        try:
            answer = _chat([{"role": "user", "content": prompt}], timeout=30).strip()
            if answer:
                return {"answer": answer, "source": "llm"}
        except Exception:
            pass
    return ask_local(question, items)


def recognize_image(image_base64: str, mime_type: str = "image/jpeg") -> dict[str, Any]:
    config = provider_config()
    if not config["configured"] or not config["vision_model"]:
        return {
            "available": False,
            "message": "服务器尚未配置支持图片的多模态模型。",
        }

    prompt = (
        "识别图片里最主要的家庭物品。只返回 JSON："
        '{"name":"物品名称","category":"日用品|医药|清洁|玩具|工具|食品|衣物|证件|电子|其他",'
        '"kind":"single|quantity|group","notes":"一句话描述"}。'
    )
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{mime_type};base64,{image_base64}"
                    },
                },
            ],
        }
    ]

    try:
        parsed = _json_from_text(
            _chat(messages, model=config["vision_model"], timeout=60)
        )
        if not parsed:
            raise RuntimeError("model did not return JSON")
        category = str(parsed.get("category", "其他"))
        if category not in DEFAULT_CATEGORIES:
            category = "其他"
        kind = str(parsed.get("kind", "single"))
        if kind not in {"single", "quantity", "group"}:
            kind = "single"
        return {
            "available": True,
            "name": str(parsed.get("name", "")).strip(),
            "category": category,
            "kind": kind,
            "notes": str(parsed.get("notes", "")).strip(),
            "source": "llm",
        }
    except Exception as error:
        return {
            "available": False,
            "message": f"图片识别失败：{error}",
        }
