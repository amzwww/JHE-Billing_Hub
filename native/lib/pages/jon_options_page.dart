import 'package:flutter/material.dart';

class JonOptionsPage extends StatelessWidget {
  const JonOptionsPage({
    super.key,
    required this.onInvoice,
    required this.onQuote,
  });

  final Future<void> Function(String type) onInvoice;
  final Future<void> Function() onQuote;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 110,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 8,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jon Hernández',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 2),
            Text(
              'Selecciona el tipo de factura',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 58, 32, 32),
              child: Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  _option(
                    context,
                    Icons.mic_none,
                    'A) Nueva factura\nponencia',
                    'Descripción autogenerada\ncon la fecha de la\nponencia.',
                    () => onInvoice('ponencia'),
                  ),
                  _option(
                    context,
                    Icons.add_circle_outline,
                    'B) Complemento a\nponencia',
                    'Cuelga de una factura\nprevia. Línea con sangría\npara gastos.',
                    () => onInvoice('complemento'),
                  ),
                  _option(
                    context,
                    Icons.emoji_events_outlined,
                    'C) Sponsor',
                    'Factura libre por\npatrocinio.',
                    () => onInvoice('sponsor'),
                  ),
                  _option(
                    context,
                    Icons.school_outlined,
                    'D) Formación',
                    'Factura por servicios de\nformación.',
                    () => onInvoice('formacion'),
                  ),
                  _option(
                    context,
                    Icons.edit_note_outlined,
                    'E) Presupuesto',
                    'Numeración JHE-PF-\nAAAA-000. Mismo formato\nque factura.',
                    onQuote,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Future<void> Function() tap,
  ) => SizedBox(
    width: 258,
    height: 390,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async => tap(),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 38, color: const Color(0xFF142A5C)),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
