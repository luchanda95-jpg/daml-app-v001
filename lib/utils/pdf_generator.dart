import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PDFGenerator {
  static Future<File> generateAgreementPDF(Map<String, dynamic> formData) async {
    final pdf = pw.Document();
    final dateFmt = DateFormat('yyyy-MM-dd');

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        build: (context) => [
          // ---------- HEADER ----------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('DIRECT ACCESS MONEY LENDING',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      )),
                  pw.Text('Client Loan Agreement',
                      style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              // Optional logo placeholder
              pw.Container(
                width: 60,
                height: 60,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey),
                  shape: pw.BoxShape.circle,
                ),
                alignment: pw.Alignment.center,
                child: pw.Text('LOGO', style: const pw.TextStyle(fontSize: 10)),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),

          // ---------- AGREEMENT TITLE ----------
          pw.Center(
            child: pw.Text('LOAN AGREEMENT FORM',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    decoration: pw.TextDecoration.underline)),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Date: ${dateFmt.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 20),

          // ---------- CLIENT INFORMATION ----------
          _sectionTitle('CLIENT DETAILS'),
          _infoRow('Full Name', formData['name']),
          _infoRow('Gender', formData['gender']),
          _infoRow('NRC Number', formData['nrc']),
          _infoRow('Mobile Number', formData['mobile']),
          _infoRow('Email Address', formData['email']),
          _infoRow('Residential Address', formData['address']),
          _infoRow('Marital Status', formData['maritalStatus']),
          pw.SizedBox(height: 10),

          // ---------- NEXT OF KIN ----------
          _sectionTitle('NEXT OF KIN DETAILS'),
          _infoRow('Primary NOK', '${formData['nok1Name']} - ${formData['nok1Mobile']}'),
          _infoRow('Address', formData['nok1Address']),
          _infoRow('Secondary NOK', '${formData['nok2Name']} - ${formData['nok2Mobile']}'),
          _infoRow('Address', formData['nok2Address']),
          pw.SizedBox(height: 10),

          // ---------- EMPLOYMENT ----------
          _sectionTitle('EMPLOYMENT DETAILS'),
          _infoRow('Employer Name', formData['employerName']),
          _infoRow('Employer Address', formData['employerAddress']),
          _infoRow('Employee No.', formData['employeeNumber']),
          _infoRow('Department', formData['department']),
          _infoRow('Supervisor Name', formData['supervisorName']),
          _infoRow('Supervisor Contact', formData['supervisorMobile']),
          pw.SizedBox(height: 10),

          // ---------- BANKING ----------
          _sectionTitle('BANKING DETAILS'),
          _infoRow('Bank Name', formData['bankName']),
          _infoRow('Branch', formData['branchName']),
          _infoRow('Account Number', formData['accountNumber']),
          _infoRow('Sort Code', formData['sortCode']),
          pw.SizedBox(height: 10),

          // ---------- LOAN DETAILS ----------
          _sectionTitle('LOAN DETAILS'),
          _infoRow('Loan Amount', formData['loanAmount']),
          _infoRow('Monthly Installment', formData['monthlyInstallment']),
          _infoRow('Start Date', formData['loanStart']),
          _infoRow('End Date', formData['loanEnd']),
          _infoRow('Mode of Payment', formData['modeOfPayment']),
          _infoRow('CRB Consent', formData['crbConsent']),
          pw.SizedBox(height: 10),

          // ---------- AGREEMENT SUMMARY ----------
          _sectionTitle('AGREEMENT TERMS'),
          pw.Text(
              'By signing this agreement, the borrower acknowledges having read and understood the terms of the loan. '
              'The borrower agrees to repay the loan according to the agreed schedule and accepts that failure to do so '
              'may result in legal or financial action by Direct Access Money Lending.',
              style: const pw.TextStyle(fontSize: 10),
              textAlign: pw.TextAlign.justify),
          pw.SizedBox(height: 10),
          pw.Text(
              'This agreement shall be governed by and construed in accordance with the laws of the Republic of Zambia.',
              style: const pw.TextStyle(fontSize: 10),
              textAlign: pw.TextAlign.justify),
          pw.SizedBox(height: 25),

          // ---------- SIGNATURE AREA ----------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBlock('Borrower Signature'),
              _signatureBlock('Loan Officer Signature'),
            ],
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10),
          ),
        ),
      ),
    );

    // ---------- SAVE FILE ----------
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/DirectAccess_Agreement_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // Helper widgets
  static pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue700,
        ),
      ),
    );
  }

  static pw.Widget _infoRow(String label, dynamic value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 150,
          child: pw.Text('$label:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        ),
        pw.Expanded(
          child: pw.Text(value?.toString() ?? '-', style: const pw.TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  static pw.Widget _signatureBlock(String title) {
    return pw.Column(
      children: [
        pw.Container(
          width: 200,
          height: 1,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: 5),
        pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 5),
        pw.Text('Date: ___________', style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
