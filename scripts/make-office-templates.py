#!/usr/bin/env python3
"""Writes the blank Office documents KeyBridge's Finder menu creates (KB-210).

Office cannot open an empty .docx, .xlsx or .pptx, so "New › Word Document"
copies one of these instead. They are written by hand here, part by part,
rather than saved from Office, so the repository holds no Microsoft file.
Each contains only what Word, Excel and PowerPoint need to open it without a
repair prompt.

Run from the repository root after changing anything below:

    scripts/make-office-templates.py
"""

import os
import zipfile

OUT = "KeyBridge/Resources/Templates"

XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
PKG = "http://schemas.openxmlformats.org/package/2006"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
OFFICE_DOC = REL + "/officeDocument"


def content_types(overrides):
    parts = "".join(
        f'<Override PartName="{name}" ContentType="{kind}"/>' for name, kind in overrides
    )
    return (
        f'{XML}<Types xmlns="{PKG}/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        f"{parts}</Types>"
    )


def rels(targets):
    items = "".join(
        f'<Relationship Id="rId{i}" Type="{kind}" Target="{target}"/>'
        for i, (kind, target) in enumerate(targets, start=1)
    )
    return f'{XML}<Relationships xmlns="{PKG}/relationships">{items}</Relationships>'


def write(name, parts):
    path = os.path.join(OUT, name)
    # A fixed timestamp keeps the files byte-identical from run to run.
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for part, text in parts.items():
            info = zipfile.ZipInfo(part, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, text)
    print(path)


def docx():
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    write("Blank.docx", {
        "[Content_Types].xml": content_types([
            ("/word/document.xml",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"),
            ("/word/settings.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"),
        ]),
        "_rels/.rels": rels([(OFFICE_DOC, "word/document.xml")]),
        "word/document.xml": f'{XML}<w:document xmlns:w="{w}"><w:body><w:p/></w:body></w:document>',
        "word/_rels/document.xml.rels": rels([(REL + "/settings", "settings.xml")]),
        # Without this Word opens the file in Compatibility Mode.
        "word/settings.xml": (
            f'{XML}<w:settings xmlns:w="{w}"><w:compat><w:compatSetting w:name="compatibilityMode" '
            'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
        ),
    })


def xlsx():
    s = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    write("Blank.xlsx", {
        "[Content_Types].xml": content_types([
            ("/xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"),
            ("/xl/worksheets/sheet1.xml",
             "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"),
        ]),
        "_rels/.rels": rels([(OFFICE_DOC, "xl/workbook.xml")]),
        "xl/workbook.xml": (
            f'{XML}<workbook xmlns="{s}" xmlns:r="{REL}">'
            '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'
        ),
        "xl/_rels/workbook.xml.rels": rels([(REL + "/worksheet", "worksheets/sheet1.xml")]),
        "xl/worksheets/sheet1.xml": f'{XML}<worksheet xmlns="{s}"><sheetData/></worksheet>',
    })


def pptx():
    p = "http://schemas.openxmlformats.org/presentationml/2006/main"
    a = "http://schemas.openxmlformats.org/drawingml/2006/main"
    ns = f'xmlns:a="{a}" xmlns:r="{REL}" xmlns:p="{p}"'
    ct = "application/vnd.openxmlformats-officedocument"
    # Every master and layout needs a shape tree, even an empty one.
    tree = (
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        "<p:grpSpPr/></p:spTree></p:cSld>"
    )
    colors = "".join(
        f"<a:{name}><a:srgbClr val=\"{value}\"/></a:{name}>"
        for name, value in [
            ("dk1", "000000"), ("lt1", "FFFFFF"), ("dk2", "44546A"), ("lt2", "E7E6E6"),
            ("accent1", "4472C4"), ("accent2", "ED7D31"), ("accent3", "A5A5A5"),
            ("accent4", "FFC000"), ("accent5", "5B9BD5"), ("accent6", "70AD47"),
            ("hlink", "0563C1"), ("folHlink", "954F72"),
        ]
    )
    solid = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    line = f'<a:ln w="6350">{solid}</a:ln>'
    theme = (
        f'{XML}<a:theme xmlns:a="{a}" name="Office Theme"><a:themeElements>'
        f'<a:clrScheme name="Office">{colors}</a:clrScheme>'
        '<a:fontScheme name="Office">'
        '<a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
        '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
        "</a:fontScheme>"
        '<a:fmtScheme name="Office">'
        f"<a:fillStyleLst>{solid * 3}</a:fillStyleLst>"
        f"<a:lnStyleLst>{line * 3}</a:lnStyleLst>"
        f"<a:effectStyleLst>{'<a:effectStyle><a:effectLst/></a:effectStyle>' * 3}</a:effectStyleLst>"
        f"<a:bgFillStyleLst>{solid * 3}</a:bgFillStyleLst>"
        "</a:fmtScheme></a:themeElements></a:theme>"
    )
    color_map = (
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" '
        'accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" '
        'folHlink="folHlink"/>'
    )
    write("Blank.pptx", {
        "[Content_Types].xml": content_types([
            ("/ppt/presentation.xml", f"{ct}.presentationml.presentation.main+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", f"{ct}.presentationml.slideMaster+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", f"{ct}.presentationml.slideLayout+xml"),
            ("/ppt/theme/theme1.xml", f"{ct}.theme+xml"),
        ]),
        "_rels/.rels": rels([(OFFICE_DOC, "ppt/presentation.xml")]),
        "ppt/presentation.xml": (
            f"{XML}<p:presentation {ns}>"
            '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
            # 16:9, PowerPoint's default for a new presentation.
            '<p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/>'
            "</p:presentation>"
        ),
        "ppt/_rels/presentation.xml.rels": rels([
            (REL + "/slideMaster", "slideMasters/slideMaster1.xml"),
            (REL + "/theme", "theme/theme1.xml"),
        ]),
        "ppt/slideMasters/slideMaster1.xml": (
            f"{XML}<p:sldMaster {ns}>{tree}{color_map}"
            '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
            "</p:sldMaster>"
        ),
        "ppt/slideMasters/_rels/slideMaster1.xml.rels": rels([
            (REL + "/slideLayout", "../slideLayouts/slideLayout1.xml"),
            (REL + "/theme", "../theme/theme1.xml"),
        ]),
        "ppt/slideLayouts/slideLayout1.xml": (
            f'{XML}<p:sldLayout {ns} type="blank">{tree}<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
            "</p:sldLayout>"
        ),
        "ppt/slideLayouts/_rels/slideLayout1.xml.rels": rels([
            (REL + "/slideMaster", "../slideMasters/slideMaster1.xml"),
        ]),
        "ppt/theme/theme1.xml": theme,
    })


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    docx()
    xlsx()
    pptx()
