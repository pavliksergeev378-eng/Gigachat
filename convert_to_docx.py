#!/usr/bin/env python3
"""Converts .md to .docx using pure Python + ZIP/XML (no external deps)."""

import os, re, zipfile, xml.sax.saxutils as saxutils

def escape(text):
    return saxutils.escape(text)

def md_to_docx(md_path, docx_path):
    with open(md_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    paragraphs = []
    in_code_block = False
    in_table = False

    for raw in lines:
        s = raw.rstrip('\n\r')

        if s.startswith('```'):
            in_code_block = not in_code_block
            if in_code_block:
                paragraphs.append(('code_block', ''))
            else:
                paragraphs.append(('code_block_end', ''))
            continue

        if in_code_block:
            if paragraphs and paragraphs[-1][0] == 'code_block':
                paragraphs[-1] = ('code_block', paragraphs[-1][1] + s + '\n')
            else:
                paragraphs.append(('code_block', s + '\n'))
            continue
        if paragraphs and paragraphs[-1][0] == 'code_block':
            paragraphs.append(('code_block_end', ''))

        if s == '---':
            continue
        if not s:
            if in_table:
                in_table = False
            continue

        if s.startswith('##### '):
            paragraphs.append(('heading5', s[6:]))
        elif s.startswith('#### '):
            paragraphs.append(('heading4', s[5:]))
        elif s.startswith('### '):
            paragraphs.append(('heading3', s[4:]))
        elif s.startswith('## '):
            paragraphs.append(('heading2', s[3:]))
        elif s.startswith('# '):
            paragraphs.append(('heading1', s[2:]))
        elif s.startswith('- '):
            text = re.sub(r'\*\*(.+?)\*\*', r'\1', s[2:])
            text = re.sub(r'`([^`]+)`', r'\1', text)
            if not text.strip():
                continue
            paragraphs.append(('bullet', text))
        elif re.match(r'^\d+[\.\)]\s', s):
            text = re.sub(r'^\d+[\.\)]\s', '', s)
            text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
            text = re.sub(r'`([^`]+)`', r'\1', text)
            paragraphs.append(('ordered', text))
        elif s.startswith('|') and s.endswith('|') and '---' in s:
            continue
        elif s.startswith('|') and s.endswith('|'):
            cells = [c.strip() for c in s.split('|')[1:-1]]
            text = ' | '.join(cells)
            text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
            paragraphs.append(('table', text))
            in_table = True
        else:
            text = re.sub(r'\*\*(.+?)\*\*', r'\1', s)
            text = re.sub(r'`([^`]+)`', r'\1', text)
            paragraphs.append(('normal', text))

    DOCX_TPL = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">
 <w:body>%s</w:body>
</w:document>'''

    NUMBERING_XML = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 mc:Ignorable="w14 wp14">
 <w:abstractNum w:abstractNumId="0">
 <w:lvl w:ilvl="0">
 <w:start w:val="1"/>
 <w:numFmt w:val="decimal"/>
 <w:lvlText w:val="%1."/>
 <w:lvlJc w:val="left"/>
 </w:lvl>
 </w:abstractNum>
 <w:num w:numId="1">
 <w:abstractNumId w:val="0"/>
 </w:num>
 <w:abstractNum w:abstractNumId="1">
 <w:lvl w:ilvl="0">
 <w:start w:val="1"/>
 <w:numFmt w:val="bullet"/>
 <w:lvlText w:val="\u2022"/>
 <w:lvlJc w:val="left"/>
 </w:lvl>
 </w:abstractNum>
 <w:num w:numId="2">
 <w:abstractNumId w:val="1"/>
 </w:num>
</w:numbering>'''

    STYLES_XML = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
 <w:style w:type="paragraph" w:styleId="Normal" w:default="1">
 <w:name w:val="Normal"/>
 <w:rPr><w:sz w:val="22"/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/></w:rPr>
 </w:style>
 <w:style w:type="paragraph" w:styleId="Heading1">
 <w:name w:val="heading 1"/>
 <w:rPr><w:b/><w:sz w:val="36"/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/></w:rPr>
 </w:style>
 <w:style w:type="paragraph" w:styleId="Heading2">
 <w:name w:val="heading 2"/>
 <w:rPr><w:b/><w:sz w:val="30"/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/></w:rPr>
 </w:style>
 <w:style w:type="paragraph" w:styleId="Heading3">
 <w:name w:val="heading 3"/>
 <w:rPr><w:b/><w:sz w:val="26"/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/></w:rPr>
 </w:style>
 <w:style w:type="paragraph" w:styleId="Heading4">
 <w:name w:val="heading 4"/>
 <w:rPr><w:b/><w:sz w:val="24"/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/></w:rPr>
 </w:style>
 <w:style w:type="paragraph" w:styleId="Heading5">
 <w:name w:val="heading 5"/>
 <w:rPr><w:b/><w:sz w:val="22"/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/></w:rPr>
 </w:style>
 <w:style w:type="paragraph" w:styleId="ListParagraph">
 <w:name w:val="List Paragraph"/>
 <w:rPr><w:sz w:val="22"/></w:rPr>
 </w:style>
</w:styles>'''

    body_parts = []
    heading_styles = {
        'heading1': 'Heading1', 'heading2': 'Heading2', 'heading3': 'Heading3',
        'heading4': 'Heading4', 'heading5': 'Heading5'
    }

    for ptype, text in paragraphs:
        if ptype == 'code_block':
            text_esc = escape(text)
            xml = '<w:p><w:pPr><w:ind w:left="360"/><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr></w:pPr>'
            for line in text_esc.split('\n'):
                xml += '<w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">' + escape(line) + '</w:t></w:r><w:r><w:br/></w:r>'
            xml += '</w:p>'
            body_parts.append(xml)
            continue
        if ptype == 'code_block_end':
            continue
        if ptype in heading_styles:
            text_esc = escape(text)
            xml = '<w:p><w:pPr><w:pStyle w:val="%s"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % (heading_styles[ptype], text_esc)
            body_parts.append(xml)
            continue
        if ptype == 'bullet':
            text_esc = escape(text)
            xml = '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr><w:ind w:left="360"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % text_esc
            body_parts.append(xml)
            continue
        if ptype == 'ordered':
            text_esc = escape(text)
            xml = '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr><w:ind w:left="360"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % text_esc
            body_parts.append(xml)
            continue
        if ptype == 'table':
            text_esc = escape(text)
            xml = '<w:p><w:r><w:t>%s</w:t></w:r></w:p>' % text_esc
            body_parts.append(xml)
            continue
        if ptype == 'normal':
            text_esc = escape(text)
            xml = '<w:p><w:r><w:t>%s</w:t></w:r></w:p>' % text_esc
            body_parts.append(xml)
            continue

    doc_xml = DOCX_TPL % '\n'.join(body_parts)

    os.makedirs(os.path.dirname(docx_path) or '.', exist_ok=True)
    with zipfile.ZipFile(docx_path, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="xml" ContentType="application/xml"/>
 <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
 <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
 <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>''')
        zf.writestr('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''')
        zf.writestr('word/_rels/document.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
 <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>''')
        zf.writestr('word/document.xml', doc_xml.encode('utf-8'))
        zf.writestr('word/styles.xml', STYLES_XML.encode('utf-8'))
        zf.writestr('word/numbering.xml', NUMBERING_XML.encode('utf-8'))

    print(f"Done: {docx_path}")
    print(f"Size: {os.path.getsize(docx_path) / 1024:.0f} KB")

if __name__ == '__main__':
    md_to_docx(
        'C:/Users/Pavel_1/Downloads/GigaChat-main/GigaChat-main/Отчёт-о-проделанной-работе.md',
        'C:/Users/Pavel_1/Downloads/GigaChat-main/GigaChat-main/Отчёт-о-проделанной-работе.docx'
    )
