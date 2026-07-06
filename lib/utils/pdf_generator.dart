import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PDFGenerator {
  static Future<File> generateAgreementPDF(Map<String, dynamic> formData) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateFmt = DateFormat('dd MMM yyyy');
    final ref = 'DAML-${now.millisecondsSinceEpoch}';

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 48,
                  height: 48,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: PdfColor.fromInt(0xFF1D4E89),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'DA',
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DIRECT ACCESS MONEY LENDING',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0B1F33)),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('CLIENT LOAN APPLICATION FORM', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Application Ref', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text(ref, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Date: ${dateFmt.format(now)}', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 2, color: PdfColor.fromInt(0xFF1D4E89)),
          ],
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Direct Access Money Lending | Confidential Application Document', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF5F8FC),
              border: pw.Border.all(color: PdfColor.fromInt(0xFFD6E2F0)),
            ),
            child: pw.Text(
              'This document was generated from the client application submitted through the Direct Access Money Lending mobile system. It is intended for official review and processing.',
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.justify,
            ),
          ),
          pw.SizedBox(height: 14),

          _sectionTitle('CLIENT DETAILS'),
          _sectionTable([
            ['Full Name', _v(formData, 'name'), 'Gender', _v(formData, 'gender')],
            ['NRC Number', _v(formData, 'nrc'), 'Mobile Number', _v(formData, 'mobile')],
            ['Email Address', _v(formData, 'email'), 'Marital Status', _v(formData, 'maritalStatus')],
            ['Residence Type', _v(formData, 'residenceType'), 'Residential Address', _v(formData, 'address')],
          ]),

          _sectionTitle('NEXT OF KIN DETAILS'),
          _sectionTable([
            ['Primary NOK', _v(formData, 'nok1Name'), 'Primary Mobile', _v(formData, 'nok1Mobile')],
            ['Primary Address', _v(formData, 'nok1Address'), 'Secondary NOK', _v(formData, 'nok2Name')],
            ['Secondary Mobile', _v(formData, 'nok2Mobile'), 'Secondary Address', _v(formData, 'nok2Address')],
          ]),

          _sectionTitle('EMPLOYMENT DETAILS'),
          _sectionTable([
            ['Employer Name', _v(formData, 'employerName'), 'Employee No.', _v(formData, 'employeeNumber')],
            ['Employer Address', _v(formData, 'employerAddress'), 'Department', _v(formData, 'department')],
            ['Supervisor Name', _v(formData, 'supervisorName'), 'Supervisor Contact', _v(formData, 'supervisorMobile')],
          ]),

          _sectionTitle('BANKING DETAILS'),
          _sectionTable([
            ['Bank Name', _v(formData, 'bankName'), 'Branch', _v(formData, 'branchName')],
            ['Account Number', _v(formData, 'accountNumber'), 'Sort Code', _v(formData, 'sortCode')],
            ['Bank NRC', _v(formData, 'bankNrc'), '', ''],
          ]),

          _sectionTitle('LOAN DETAILS'),
          _sectionTable([
            ['Loan Amount', _v(formData, 'loanAmount'), 'Monthly Installment', _v(formData, 'monthlyInstallment')],
            ['Loan Start Date', _v(formData, 'loanStart'), 'Loan End Date', _v(formData, 'loanEnd')],
            ['Mode of Payment', _v(formData, 'modeOfPayment'), 'CRB Consent', _v(formData, 'crbConsent')],
          ]),

          pw.NewPage(),
          _sectionTitle('DECLARATION AND TERMS'),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'The applicant declares that the information provided in this application is true, correct, and complete to the best of their knowledge.',
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.justify,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'By submitting this application, the applicant authorises Direct Access Money Lending to verify the supplied details, including CRB checks where consent has been given, and to process the application according to its internal lending procedures and applicable laws of the Republic of Zambia.',
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.justify,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 34),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBlock('Applicant Signature'),
              _signatureBlock('Authorised Officer'),
            ],
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final safeName = _safeFileSegment(_v(formData, 'name', fallback: 'client'));
    final file = File('${dir.path}/DirectAccess_Application_${safeName}_${now.millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static String _v(Map<String, dynamic> data, String key, {String fallback = '—'}) {
    final value = data[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
  }

  static String _safeFileSegment(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'client' : safe;
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF1D4E89)),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _sectionTable(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
      columnWidths: const {
        0: pw.FixedColumnWidth(95),
        1: pw.FlexColumnWidth(1),
        2: pw.FixedColumnWidth(95),
        3: pw.FlexColumnWidth(1),
      },
      children: rows.map((row) {
        return pw.TableRow(
          children: [
            _labelCell(row[0]),
            _valueCell(row[1]),
            _labelCell(row.length > 2 ? row[2] : ''),
            _valueCell(row.length > 3 ? row[3] : ''),
          ],
        );
      }).toList(),
    );
  }

  static pw.Widget _labelCell(String label) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      color: PdfColor.fromInt(0xFFF2F2F2),
      child: pw.Text(label, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _valueCell(String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(value.isEmpty ? '—' : value, style: const pw.TextStyle(fontSize: 8.5)),
    );
  }

  static pw.Widget _signatureBlock(String title) {
    return pw.Container(
      width: 220,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(height: 1, color: PdfColors.black),
          pw.SizedBox(height: 5),
          pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Date: ______________________', style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }
}

