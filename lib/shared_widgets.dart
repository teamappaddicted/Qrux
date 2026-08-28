import 'package:flutter/material.dart';

class PageShell extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  const PageShell({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IconButton(
                  alignment: Alignment.centerLeft,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 32),
                child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class InputField extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool obscure;
  final TextEditingController? controller;
  const InputField({
    required this.label,
    required this.icon,
    this.obscure = false,
    this.controller,
    super.key,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: InputBorder.none,
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

class RoleTile extends StatelessWidget {
  final String title, detail;
  final IconData icon;
  final VoidCallback onTap;
  final bool muted;
  const RoleTile({
    required this.title,
    required this.detail,
    required this.icon,
    required this.onTap,
    this.muted = false,
    super.key,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(20),
      color: muted ? Colors.white : Colors.black,
      child: Row(
        children: [
          Icon(icon, color: muted ? Colors.black : Colors.white, size: 28),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: muted ? Colors.black : Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: TextStyle(
                    color: muted ? Colors.black54 : Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward, color: muted ? Colors.black : Colors.white),
        ],
      ),
    ),
  );
}

class Metric extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final VoidCallback? onTap;
  const Metric(this.value, this.label, this.icon, {this.onTap, super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ActionRow extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final VoidCallback onTap;
  const ActionRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    super.key,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black,
      child: Icon(icon, color: Colors.white, size: 20),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    subtitle: Text(detail),
    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
  );
}

class Detail extends StatelessWidget {
  final String label, value;
  const Detail(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.2,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

class Control extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const Control(
    this.label,
    this.icon,
    this.onTap, {
    this.filled = false,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(7),
    child: InkWell(
      onTap: onTap,
      child: Container(
        width: 92,
        height: 76,
        color: filled ? Colors.black : Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? Colors.white : Colors.black, size: 28),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: filled ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
