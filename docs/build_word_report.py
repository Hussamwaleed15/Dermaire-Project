import os
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

# DERMAIRE BRAND PALETTE (Extracted directly from the official logo)
# Primary Deep Wine / Burgundy
COLOR_PRIMARY_HEX = "4A0E17"
COLOR_PRIMARY_RGB = RGBColor(0x4A, 0x0E, 0x17)

# Secondary Rose Wine / Warm Burgundy
COLOR_SECONDARY_HEX = "7B2D38"
COLOR_SECONDARY_RGB = RGBColor(0x7B, 0x2D, 0x38)

# Tertiary Muted Rose / Warm Accent
COLOR_ACCENT_HEX = "9E4753"
COLOR_ACCENT_RGB = RGBColor(0x9E, 0x47, 0x53)

# Soft Warm Blush / Beige Tint for Callouts and Table Alternate Rows
COLOR_BG_LIGHT_HEX = "FAF3EE"
COLOR_BG_ALT_HEX = "FBF6F2"

# Body Dark Text (Warm Charcoal)
COLOR_BODY_RGB = RGBColor(0x2C, 0x22, 0x24)

def set_cell_background(cell, fill_hex):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{fill_hex}"/>')
    tcPr.append(shd)

def set_cell_margins(cell, top=140, bottom=140, left=200, right=200):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(f'<w:tcMar {nsdecls("w")}><w:top w:w="{top}" w:type="dxa"/><w:bottom w:w="{bottom}" w:type="dxa"/><w:left w:w="{left}" w:type="dxa"/><w:right w:w="{right}" w:type="dxa"/></w:tcMar>')
    tcPr.append(tcMar)

def add_styled_heading(doc, text, level):
    h = doc.add_heading(level=level)
    h_format = h.paragraph_format
    h_format.space_before = Pt(14)
    h_format.space_after = Pt(6)
    h_format.keep_with_next = True
    
    run = h.add_run(text)
    run.font.name = 'Georgia'
    if level == 1:
        run.font.size = Pt(17)
        run.font.bold = True
        run.font.color.rgb = COLOR_PRIMARY_RGB
    elif level == 2:
        run.font.size = Pt(13.5)
        run.font.bold = True
        run.font.color.rgb = COLOR_SECONDARY_RGB
    elif level == 3:
        run.font.size = Pt(11.5)
        run.font.bold = True
        run.font.color.rgb = COLOR_ACCENT_RGB
    return h

def add_callout_box(doc, text, title=None):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = tbl.cell(0, 0)
    set_cell_background(cell, COLOR_BG_LIGHT_HEX)
    set_cell_margins(cell, top=160, bottom=160, left=240, right=240)
    
    # Left border highlight in brand wine
    tcPr = cell._tc.get_or_add_tcPr()
    borders = parse_xml(f'<w:tcBorders {nsdecls("w")}><w:top w:val="none"/><w:left w:val="single" w:sz="24" w:space="0" w:color="{COLOR_PRIMARY_HEX}"/><w:bottom w:val="none"/><w:right w:val="none"/></w:tcBorders>')
    tcPr.append(borders)
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(2)
    if title:
        rt = p.add_run(f"{title}\n")
        rt.bold = True
        rt.font.name = 'Georgia'
        rt.font.size = Pt(11)
        rt.font.color.rgb = COLOR_PRIMARY_RGB
    
    rtxt = p.add_run(text)
    rtxt.font.name = 'Calibri'
    rtxt.font.size = Pt(10.5)
    rtxt.font.italic = True
    rtxt.font.color.rgb = COLOR_BODY_RGB
    
    # Spacing paragraph
    sp = doc.add_paragraph()
    sp.paragraph_format.space_before = Pt(0)
    sp.paragraph_format.space_after = Pt(6)

def build_word_report():
    doc = Document()
    
    # Page Margins
    for section in doc.sections:
        section.top_margin = Inches(0.9)
        section.bottom_margin = Inches(0.9)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)
        
    # Official Logo Path (Downloaded exact logo image from Discord)
    logo_path = r"c:\Users\Hossam\Desktop\Dermaire-Project\backend\static\input_image_1.png"
    if not os.path.exists(logo_path):
        logo_path = r"c:\Users\Hossam\Desktop\Dermaire-Project\backend\static\dermaire-logo.jpg"
    
    # Top Branding Header Table
    header_table = doc.add_table(rows=1, cols=2)
    header_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    header_table.autofit = False
    
    cell_logo = header_table.cell(0, 0)
    cell_logo.width = Inches(2.2)
    cell_title = header_table.cell(0, 1)
    cell_title.width = Inches(4.3)
    
    if os.path.exists(logo_path):
        p_logo = cell_logo.paragraphs[0]
        p_logo.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run_logo = p_logo.add_run()
        run_logo.add_picture(logo_path, width=Inches(1.9))
    
    p_title = cell_title.paragraphs[0]
    p_title.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p_title.paragraph_format.space_before = Pt(10)
    
    r_brand = p_title.add_run("DERMAIRE\n")
    r_brand.font.name = 'Georgia'
    r_brand.font.size = Pt(26)
    r_brand.font.bold = True
    r_brand.font.color.rgb = COLOR_PRIMARY_RGB
    
    r_sub = p_title.add_run("Smart Care for Your Skin — Personal Skin Lab\n")
    r_sub.font.name = 'Calibri'
    r_sub.font.size = Pt(12)
    r_sub.font.bold = True
    r_sub.font.color.rgb = COLOR_SECONDARY_RGB
    
    r_doc_type = p_title.add_run("Single-Subject (N-of-1) Clinical Experiment Engine\nExecutive Concept & Technical Architecture Dossier\nTarget: Technical Evaluators & Healthcare AI Reviewers")
    r_doc_type.font.name = 'Calibri'
    r_doc_type.font.size = Pt(9.5)
    r_doc_type.font.color.rgb = COLOR_ACCENT_RGB
    
    # Elegant Divider line in Brand Wine
    divider = doc.add_paragraph()
    divider.paragraph_format.space_before = Pt(10)
    divider.paragraph_format.space_after = Pt(14)
    pBdr = parse_xml(f'<w:pBdr {nsdecls("w")}><w:bottom w:val="single" w:sz="16" w:space="4" w:color="{COLOR_PRIMARY_HEX}"/></w:pBdr>')
    divider._p.get_or_add_pPr().append(pBdr)
    
    # 1. Executive Summary & Problem Definition
    add_styled_heading(doc, "1. Executive Summary & Problem Definition", level=1)
    
    add_callout_box(
        doc,
        "\"Dermaire is not a cosmetic beauty filter or a naive photo-analysis app that dispenses generic marketing advice. It is an evidence-based, clinical-grade digital laboratory engine for single-subject (N-of-1) controlled self-experiments, rooted in the scientific principles of dermatology.\"",
        title="Core Project Thesis"
    )
    
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(8)
    r = p.add_run("Millions of consumers spend billions of dollars each year on active skincare products while operating entirely in the dark. Current consumer digital skincare solutions fail to address four critical clinical challenges:")
    r.font.name = 'Calibri'
    r.font.size = Pt(11)
    r.font.color.rgb = COLOR_BODY_RGB
    
    bullets = [
        ("The Confounding Factors Dilemma: ", "If skin appears redder or oilier today, is it a negative reaction to a new serum, or simply the result of 90% ambient humidity, seasonal temperature shifts, or hormonal cycle fluctuations?"),
        ("The 'Selfie Angle & Lighting' Bias: ", "Standard smartphone selfies taken at slightly different angles, distances, or room lighting trigger catastrophic false variances in computer vision algorithms, rendering existing consumer skincare apps scientifically invalid."),
        ("Chemical Conflict Hazards: ", "Consumers unknowingly layer incompatible active ingredients (e.g., Retinoids paired with potent AHA/BHA chemical peels, or Benzoyl Peroxide), destroying the skin's protective lipid barrier and triggering acute chemical dermatitis."),
        ("The Clinician Data Void: ", "When patients visit a dermatologist, they cannot accurately recall what formulations they introduced, when the adverse reaction started, or how their skin responded over the preceding 28 days.")
    ]
    
    for bold_prefix, text in bullets:
        bp = doc.add_paragraph(style='List Bullet')
        bp.paragraph_format.space_after = Pt(4)
        r1 = bp.add_run(bold_prefix)
        r1.bold = True
        r1.font.name = 'Calibri'
        r1.font.size = Pt(10.5)
        r1.font.color.rgb = COLOR_PRIMARY_RGB
        r2 = bp.add_run(text)
        r2.font.name = 'Calibri'
        r2.font.size = Pt(10.5)
        r2.font.color.rgb = COLOR_BODY_RGB
        
    p_trans = doc.add_paragraph()
    p_trans.paragraph_format.space_before = Pt(6)
    p_trans.paragraph_format.space_after = Pt(12)
    rt = p_trans.add_run("Dermaire transforms skincare from subjective guesswork into measurable, reproducible, and clinically verifiable science.")
    rt.font.name = 'Georgia'
    rt.font.size = Pt(11)
    rt.font.bold = True
    rt.font.color.rgb = COLOR_PRIMARY_RGB

    # 2. Core Scientific Concept: The N-of-1 Experiment Engine
    add_styled_heading(doc, "2. Core Scientific Concept: The N-of-1 Experiment Engine", level=1)
    
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(8)
    r = p.add_run("Human skin is an idiosyncratic biological organ. In dermatology, there is no generic 'average skin' that responds universally to blanket recommendations. Dermaire solves this via the N-of-1 Clinical Trial Methodology:")
    r.font.name = 'Calibri'
    r.font.size = Pt(11)
    r.font.color.rgb = COLOR_BODY_RGB
    
    add_callout_box(
        doc,
        "[Standardized Guided Capture] + [Single-Variable Isolation] + [Environmental Confounder Subtraction] = True Biological Outcome (Delta %)",
        title="The Dermaire Mathematical Formulation"
    )
    
    n_points = [
        ("1. Strict Variable Isolation: ", "The system enforces a mandatory clinical isolation rule: only one active formulation can be introduced during an experimental cycle. Adding a secondary active product is prohibited or requires freezing/completing the current experiment to prevent multi-variable contamination."),
        ("2. Personal Baseline Calibration (Days 1–5): ", "The user is never evaluated against arbitrary global ideals. During the initial 3 to 5 calibration days, the system records consecutive measurements under neutral conditions to establish the user's personal baseline (mean μ and standard deviation σ for hydration proxy, surface roughness, and erythema index). All subsequent changes during the trial are computed as a relative delta percentage (Δ%) against the user's own baseline."),
        ("3. Confounding Factor Neutralization: ", "Every skin check-in is programmatically synchronized with local meteorological metrics (temperature, relative humidity via Weather APIs) and hormonal cycle milestones. When the system detects anomalous weather or hormonal peaks, it statistically normalizes or isolates those days, ensuring external fluctuations are never misattributed to the product.")
    ]
    for bold_prefix, text in n_points:
        np_p = doc.add_paragraph()
        np_p.paragraph_format.space_after = Pt(6)
        r1 = np_p.add_run(bold_prefix)
        r1.bold = True
        r1.font.name = 'Calibri'
        r1.font.size = Pt(11)
        r1.font.color.rgb = COLOR_PRIMARY_RGB
        r2 = np_p.add_run(text)
        r2.font.name = 'Calibri'
        r2.font.size = Pt(10.5)
        r2.font.color.rgb = COLOR_BODY_RGB

    # 3. Strategic Project Objectives
    add_styled_heading(doc, "3. Strategic Project Objectives", level=1)
    
    objs = [
        ("Democratize Controlled Clinical Trials: ", "Provide everyday consumers with a scientifically validated methodology to prove whether a skincare product genuinely benefits their specific skin barrier."),
        ("Prevent Acute Chemical Skin Injuries: ", "Protect users from barrier degradation and chemical burns via a deterministic interaction checker that validates active formulations prior to application."),
        ("Empower Dermatologists with High-Fidelity Data: ", "Bridge the gap between daily home care and clinical consultations by equipping clinicians with verifiable 28-day longitudinal trajectories rather than unreliable patient anecdotes."),
        ("Uphold Responsible AI and Zero-Biometric-Leakage: ", "Guarantee absolute biometric privacy by processing facial features on-device and adhering strictly to non-diagnostic medical boundaries with automated bilingual emergency escalation.")
    ]
    for b_title, b_desc in objs:
        op = doc.add_paragraph(style='List Bullet')
        op.paragraph_format.space_after = Pt(4)
        r1 = op.add_run(b_title)
        r1.bold = True
        r1.font.name = 'Calibri'
        r1.font.size = Pt(10.5)
        r1.font.color.rgb = COLOR_PRIMARY_RGB
        r2 = op.add_run(b_desc)
        r2.font.name = 'Calibri'
        r2.font.size = Pt(10.5)
        r2.font.color.rgb = COLOR_BODY_RGB

    # 4. End-to-End System Workflow
    add_styled_heading(doc, "4. End-to-End System Workflow", level=1)
    
    steps = [
        ("Step 1: Onboarding & Baseline Profiling", "Establish skin phenotype, primary concerns, and catalog current active formulations into a typed inventory."),
        ("Step 2: Deterministic Conflict Screening", "Pre-screen products through an evidence-based chemical conflict matrix before trials begin, blocking hazardous combinations."),
        ("Step 3: Baseline Calibration Phase (Days 1–5)", "Record baseline sessions under neutral conditions to mathematically establish the user's natural physiological baseline."),
        ("Step 4: Daily Standardized Guided Check-In", "Real-time ML Kit face tracking guides the user to match reference angle, roll, pitch, and lighting. On-device processing extracts a privacy-safe numeric Feature Vector (Redness, Texture, Hydration), while ambient meteorological data is synced automatically."),
        ("Step 5: Longitudinal Delta Analysis & Educational Assistant", "Calculate true biological delta (Δ%) isolated from weather and hormonal confounders. Provide educational guidance via an AI Assistant strictly bounded by non-diagnostic rules."),
        ("Step 6: Generative Clinical Summary & Clinician Sharing", "Compile an evidence-based clinical narrative synthesized by Azure OpenAI GPT-4o. Share full longitudinal charts with the clinician via an ephemeral, time-limited encrypted QR link.")
    ]
    
    tbl_flow = doc.add_table(rows=len(steps) + 1, cols=2)
    tbl_flow.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_flow.autofit = False
    
    hdr_cells = tbl_flow.rows[0].cells
    hdr_cells[0].width = Inches(2.2)
    hdr_cells[1].width = Inches(4.3)
    hdr_cells[0].text = "Phase / Step"
    hdr_cells[1].text = "Clinical & Technical Execution"
    for c in hdr_cells:
        set_cell_background(c, COLOR_PRIMARY_HEX)
        set_cell_margins(c, top=140, bottom=140, left=160, right=160)
        p = c.paragraphs[0]
        p.runs[0].font.bold = True
        p.runs[0].font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        p.runs[0].font.name = 'Georgia'
        p.runs[0].font.size = Pt(10.5)
        
    for i, (st, desc) in enumerate(steps):
        row_cells = tbl_flow.rows[i+1].cells
        row_cells[0].width = Inches(2.2)
        row_cells[1].width = Inches(4.3)
        row_cells[0].text = st
        row_cells[1].text = desc
        bg_color = COLOR_BG_ALT_HEX if i % 2 == 0 else "FFFFFF"
        for c in row_cells:
            set_cell_background(c, bg_color)
            set_cell_margins(c, top=100, bottom=100, left=160, right=160)
            p = c.paragraphs[0]
            p.runs[0].font.name = 'Calibri'
            p.runs[0].font.size = Pt(10)
            p.runs[0].font.color.rgb = COLOR_BODY_RGB
        row_cells[0].paragraphs[0].runs[0].font.bold = True
        row_cells[0].paragraphs[0].runs[0].font.color.rgb = COLOR_PRIMARY_RGB
        
    # Spacer
    sp = doc.add_paragraph()
    sp.paragraph_format.space_before = Pt(4)
    sp.paragraph_format.space_after = Pt(8)

    # 5. Technical Architecture & Innovation
    add_styled_heading(doc, "5. Technical Architecture & Innovation: Where & How It Operates", level=1)
    
    add_styled_heading(doc, "5.1 Deployment & Platform Footprint (Where It Lives)", level=2)
    
    arch_bullets = [
        ("Patient Mobile Client: ", "A cross-platform mobile application targeting iOS and Android built with Flutter (Dart). Flutter provides single-codebase velocity, 60 FPS rendering pipeline, and direct control over hardware camera streams and real-time canvas overlays (CustomPainter)."),
        ("Clinician Web Workspace: ", "A responsive clinical portal accessible by verified dermatologists on clinic workstations to inspect longitudinal patient trajectories."),
        ("Cloud & Serverless API Gateway: ", "A high-performance, asynchronous Python FastAPI backend deployed on Microsoft Azure (scalable as Azure Container Apps or Serverless Azure Functions) backed by enterprise PostgreSQL / Cosmos DB storage.")
    ]
    for b_title, b_desc in arch_bullets:
        bp = doc.add_paragraph(style='List Bullet')
        bp.paragraph_format.space_after = Pt(4)
        r1 = bp.add_run(b_title)
        r1.bold = True
        r1.font.name = 'Calibri'
        r1.font.size = Pt(10.5)
        r1.font.color.rgb = COLOR_PRIMARY_RGB
        r2 = bp.add_run(b_desc)
        r2.font.name = 'Calibri'
        r2.font.size = Pt(10.5)
        r2.font.color.rgb = COLOR_BODY_RGB
        
    add_styled_heading(doc, "5.2 Key Technical Engines & Architectural Highlights (How It Works)", level=2)
    
    engines = [
        ("1. Standardized Guided Capture (Real-Time Alignment): ", "Integrated Flutter Camera API with google_mlkit_face_detection. Performs real-time geometric tracking of the user's face position, distance, and 3D Euler angles (Roll, Pitch, Yaw). Visual cues guide the user until their face matches reference baseline coordinates by ≥ 90%, eliminating false algorithmic variance."),
        ("2. On-Device Edge Extraction & Data Minimization: ", "Leverages lightweight on-device machine learning (TFLite / ML Kit). Daily check-ins extract a compact numeric Feature Vector [erythema_index, surface_roughness_metric, hydration_proxy] directly on the handset. Raw biometric facial images never leave the device during routine tracking, ensuring strict GDPR/HIPAA-aligned data minimization."),
        ("3. Deterministic Chemical Conflict Matrix: ", "A medically codified, zero-hallucination lookup matrix with ingredient synonym normalization. In high-risk chemical interactions (e.g., Tretinoin + Glycolic Acid, Benzoyl Peroxide + Retinol, Vitamin C + Copper Peptides), the system deliberately rejects generative AI guessing. It enforces hardcoded, peer-reviewed clinical rules to guarantee patient safety."),
        ("4. Microsoft Azure AI Integration (Dual Genuine AI Services): ", "Azure AI Vision 4.0 performs clinical-grade quantitative feature evaluation (erythema/redness ratios, texture variance, and luminance validation) with verified accuracy. Azure OpenAI GPT-4o / AI Foundry synthesizes raw longitudinal data points, percentage deltas, and user symptom notes into an intelligible, structured narrative report for both the patient and dermatologist under strict non-diagnostic prompt guardrails."),
        ("5. Real-Time Clinical Red-Flag Escalation (Azure AI Content Safety): ", "Monitors patient interactions in real time across both English and Arabic for life-threatening symptoms (facial/lip swelling, acute breathing distress, anaphylaxis, spreading rashes). The system immediately interrupts standard operation and presents a high-priority emergency advisory directing the user to the nearest urgent care facility."),
        ("6. Clinician Gateway & Ephemeral QR Linking (Zero-Trust Security): ", "Cryptographically signed, short-lived JSON Web Tokens (JWT) mapped to dynamic QR payloads. Access is granted strictly via an ephemeral token with a 15- to 60-minute time-to-live (TTL). The patient retains full sovereignty, with the ability to instantly revoke clinician access with a single tap, backed by immutable audit logs.")
    ]
    for b_title, b_desc in engines:
        ep = doc.add_paragraph()
        ep.paragraph_format.space_after = Pt(6)
        r1 = ep.add_run(b_title)
        r1.bold = True
        r1.font.name = 'Calibri'
        r1.font.size = Pt(11)
        r1.font.color.rgb = COLOR_PRIMARY_RGB
        r2 = ep.add_run(b_desc)
        r2.font.name = 'Calibri'
        r2.font.size = Pt(10.5)
        r2.font.color.rgb = COLOR_BODY_RGB

    # 6. What We Deliberately Excluded & Why
    add_styled_heading(doc, "6. What We Deliberately Excluded & Why (Architectural Integrity)", level=1)
    
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(8)
    r = p.add_run("Many technology competition entries artificially inflate their stack with irrelevant cloud services to appear sophisticated (e.g., Azure IoT Hub, Stream Analytics, Azure Data Explorer). Our engineering team deliberately excluded these components:")
    r.font.name = 'Calibri'
    r.font.size = Pt(11)
    r.font.color.rgb = COLOR_BODY_RGB
    
    add_callout_box(
        doc,
        "\"Dermaire is an event-driven digital healthcare platform based on structured daily user interactions, not an industrial factory floor streaming thousands of high-frequency telemetry packets per second. Senior engineering is defined by choosing the simplest, most robust tool that solves the real-world problem with uncompromising integrity.\"",
        title="Statement of Engineering Integrity"
    )

    # 7. Strategic Impact & Comparative Value Proposition
    add_styled_heading(doc, "7. Strategic Impact & Comparative Value Proposition", level=1)
    
    comp_data = [
        ("Underlying Approach", "Generic cosmetic advice & product affiliate sales", "Single-Subject (N-of-1) controlled clinical trials"),
        ("Capture Integrity", "Unregulated, random selfie angles and lighting", "Standardized Guided Capture with real-time pose locking"),
        ("Environmental Bias", "Ignored completely (weather causes false alarms)", "Confounding variables (weather, humidity, cycle) isolated"),
        ("Chemical Safety", "None, or unverified AI chatbot guessing", "Deterministic, peer-reviewed chemical conflict matrix"),
        ("Biometric Privacy", "Unencrypted facial photos uploaded to servers", "On-device edge vector extraction (Data Minimization)"),
        ("Dermatologist Value", "Useless, fragmented cosmetic self-reports", "Longitudinal data charts via zero-trust, ephemeral QR access"),
        ("Emergency Safety", "No clinical guardrails or red-flag detection", "Real-time bilingual emergency escalation (Azure Safety)")
    ]
    
    tbl_comp = doc.add_table(rows=len(comp_data) + 1, cols=3)
    tbl_comp.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_comp.autofit = False
    
    c_widths = [Inches(1.8), Inches(2.3), Inches(2.4)]
    hdr_titles = ["Evaluation Dimension", "Traditional Skincare Apps", "DERMAIRE (Personal Skin Lab)"]
    for j, cell in enumerate(tbl_comp.rows[0].cells):
        cell.width = c_widths[j]
        cell.text = hdr_titles[j]
        set_cell_background(cell, COLOR_PRIMARY_HEX)
        set_cell_margins(cell, top=120, bottom=120, left=140, right=140)
        p = cell.paragraphs[0]
        p.runs[0].font.bold = True
        p.runs[0].font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        p.runs[0].font.name = 'Georgia'
        p.runs[0].font.size = Pt(10)
        
    for i, row in enumerate(comp_data):
        row_cells = tbl_comp.rows[i+1].cells
        bg_col = COLOR_BG_ALT_HEX if i % 2 == 0 else "FFFFFF"
        for j, cell in enumerate(row_cells):
            cell.width = c_widths[j]
            cell.text = row[j]
            set_cell_background(cell, bg_col)
            set_cell_margins(cell, top=100, bottom=100, left=140, right=140)
            p = cell.paragraphs[0]
            p.runs[0].font.name = 'Calibri'
            p.runs[0].font.size = Pt(9.5)
            p.runs[0].font.color.rgb = COLOR_BODY_RGB
            if j == 0:
                p.runs[0].font.bold = True
                p.runs[0].font.color.rgb = COLOR_PRIMARY_RGB
            elif j == 2:
                p.runs[0].font.bold = True
                p.runs[0].font.color.rgb = COLOR_SECONDARY_RGB

    # 8. Conclusion for the Evaluation Committee
    add_styled_heading(doc, "8. Conclusion for the Evaluation Committee", level=1)
    
    p_concl = doc.add_paragraph()
    p_concl.paragraph_format.space_before = Pt(6)
    p_concl.paragraph_format.space_after = Pt(14)
    rc = p_concl.add_run("DERMAIRE represents a paradigm shift in digital dermatology. By replacing subjective beauty claims with rigorous single-user clinical methodology, standardizing computer-vision capture, preserving patient biometric sovereignty, and leveraging the Microsoft Azure AI ecosystem responsibly, Dermaire provides a credible, impactful, and production-ready solution worthy of selection and championship in the competition.")
    rc.font.name = 'Georgia'
    rc.font.size = Pt(11)
    rc.font.bold = True
    rc.font.color.rgb = COLOR_PRIMARY_RGB
    
    output_path = r"c:\Users\Hossam\Desktop\Dermaire-Project\docs\DERMAIRE_Executive_Technical_Report.docx"
    doc.save(output_path)
    print(f"Successfully generated executive Word document with brand colors at: {output_path}")

if __name__ == "__main__":
    build_word_report()
