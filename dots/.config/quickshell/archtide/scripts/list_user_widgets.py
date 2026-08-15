#!/usr/bin/env python3
import os
import json
import sys

def main():
    config_dir = os.path.expanduser("~/.config/quickshell/ii")
    user_widgets_dir = os.path.join(config_dir, "user_widgets")
    
    # Ensure the directory exists
    os.makedirs(user_widgets_dir, exist_ok=True)
    
    widgets = []
    
    if not os.path.exists(user_widgets_dir):
        print(json.dumps([]))
        return

    for item in os.listdir(user_widgets_dir):
        item_path = os.path.join(user_widgets_dir, item)
        if os.path.isdir(item_path):
            meta_path = os.path.join(item_path, "metadata.json")
            if os.path.exists(meta_path):
                try:
                    with open(meta_path, "r", encoding="utf-8") as f:
                        meta = json.load(f)
                    
                    widget_id = meta.get("widgetId", item)
                    qml_entry = meta.get("qmlEntry", "main.qml")
                    qml_path = os.path.join(item_path, qml_entry)
                    
                    if os.path.exists(qml_path):
                        widgets.append({
                            "widgetId": widget_id,
                            "name": meta.get("name", item.replace("_", " ").title()),
                            "category": meta.get("category", "Custom"),
                            "qmlPath": "file://" + qml_path,
                            "icon": meta.get("icon", "extension"),
                            "description": meta.get("description", "A custom widget.")
                        })
                except Exception as e:
                    sys.stderr.write(f"Error loading widget {item}: {e}\n")
                    
    print(json.dumps(widgets))

if __name__ == "__main__":
    main()
