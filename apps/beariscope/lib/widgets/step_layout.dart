import 'package:material_ui/material_ui.dart';

/// A consistent step layout used inside sign-up / onboarding flows.
///
/// Renders a [title] at the top, a scrollable [body] area below it, and a
/// sticky action button at the bottom. The entire layout is centred and
/// constrained to a sensible max-width (600 px).
class StepLayout extends StatelessWidget {
  /// The bold heading shown at the top of the step.
  final String title;

  /// The scrollable content below the title (description, form fields, cards,
  /// etc.).
  final Widget body;

  /// Label for the sticky action button.
  final String buttonText;

  /// Icon for the sticky action button.
  final IconData buttonIcon;

  /// Called when the action button is tapped.
  ///
  /// When `null` the button is disabled (greyed out). This is useful when form
  /// validation prevents submission.
  final VoidCallback? onButtonPressed;

  /// When `true` the button is disabled and shows a [CircularProgressIndicator].
  final bool isLoading;

  /// Optional label for a secondary text button rendered above the primary
  /// button (e.g. "Skip for now").
  final String? secondaryButtonText;

  /// Called when the secondary text button is tapped.
  final VoidCallback? onSecondaryButtonPressed;

  const StepLayout({
    super.key,
    required this.title,
    required this.body,
    required this.buttonText,
    required this.buttonIcon,
    this.onButtonPressed,
    this.isLoading = false,
    this.secondaryButtonText,
    this.onSecondaryButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      body,
                    ],
                  ),
                ),
              ),
            ),
            if (secondaryButtonText != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Center(
                  child: TextButton(
                    onPressed: onSecondaryButtonPressed,
                    child: Text(secondaryButtonText!),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: isLoading || onButtonPressed == null
                    ? null
                    : onButtonPressed,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(buttonIcon),
                label: Text(isLoading ? 'Processing...' : buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
