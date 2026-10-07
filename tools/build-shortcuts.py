#!/usr/bin/env python3
"""Build token-free iOS Shortcuts. Sign outputs with macOS `shortcuts sign`."""

import pathlib
import plistlib
import uuid


ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tools" / "unsigned-shortcuts"


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "clbswrs.co/stream/" + name)).upper()


def variable(value):
    return {"WFSerializationType": "WFTextTokenAttachment", "Value": value}


def result(name):
    return variable({"Type": "ActionOutput", "OutputUUID": identifier(name),
                     "OutputName": name})


def text(parts):
    string = ""
    attachments = {}
    for part in parts:
        if isinstance(part, str):
            string += part
        else:
            attachments[f"{{{len(string)}, 1}}"] = part["Value"]
            string += "\ufffc"
    return {"WFSerializationType": "WFTextTokenString", "Value": {
        "string": string, "attachmentsByRange": attachments}}


def action(kind, name, **parameters):
    return {"WFWorkflowActionIdentifier": "is.workflow.actions." + kind,
            "WFWorkflowActionParameters": {"UUID": identifier(name), **parameters}}


def workflow(name, actions, input_classes=(), questions=()):
    return {
        "WFWorkflowName": name,
        "WFWorkflowClientVersion": "4000.1.1",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983,
                           "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowTypes": ["ActionExtension"] if input_classes else [],
        "WFWorkflowInputContentItemClasses": list(input_classes),
        "WFWorkflowHasShortcutInputVariables": bool(input_classes),
        "WFWorkflowImportQuestions": list(questions),
        "WFWorkflowActions": actions,
    }


def quotation(name, mode):
    # The page receives no token or pairing key. The native Text action below
    # appends the key only after the page's JavaScript has finished.
    script = (ROOT / "tools" / "safari-selection.js").read_text().replace(
        "MODE", mode)
    return workflow(name, [
        action("gettext", name + " pairing", WFTextActionText="PAIRING_KEY"),
        action("runjavascriptonwebpage", name + " selection",
               WFInput=variable({"Type": "ExtensionInput"}), WFJavaScript=script),
        action("gettext", name + " destination", WFTextActionText=text([
            "https://clbswrs.co/stream/post/#payload=", result(name + " selection"),
            "&key=", result(name + " pairing")])),
        action("openurl", name + " open", WFInput=result(name + " destination")),
    ], ["WFSafariWebPageContentItem"], [{
        "ActionIndex": 0, "Category": "Parameter", "ParameterKey": "WFTextActionText",
        "Text": "Paste the pairing key from clbswrs.co/stream/post/ → Phone setup.",
        "DefaultValue": "PAIRING_KEY",
    }])


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    workflows = [
        quotation("Quote to stream", "auto"),
        quotation("Quote with reaction", "compose"),
        workflow("Note to stream", [
            action("gettext", "note destination", WFTextActionText=
                   "https://clbswrs.co/stream/post/"),
            action("openurl", "note open", WFInput=result("note destination")),
        ]),
        workflow("Share to stream", [
            action("gettext", "shared text", WFTextActionText=text([
                variable({"Type": "ExtensionInput"})])),
            action("urlencode", "encoded share", WFInput=result("shared text"),
                   WFEncodeMode="Encode"),
            action("gettext", "shared destination", WFTextActionText=text([
                "https://clbswrs.co/stream/post/#shared=", result("encoded share")])),
            action("openurl", "shared open", WFInput=result("shared destination")),
        ], ["WFStringContentItem", "WFURLContentItem", "WFRichTextContentItem"]),
    ]
    for item in workflows:
        path = OUTPUT / (item["WFWorkflowName"].lower().replace(" ", "-") + ".shortcut")
        path.write_bytes(plistlib.dumps(item, fmt=plistlib.FMT_BINARY, sort_keys=False))
        print(path.name)


if __name__ == "__main__":
    build()
