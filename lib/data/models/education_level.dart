/// Self-reported education level, captured at sign-up.
///
/// Drives personalisation later (lesson depth, Q&A difficulty, which advanced
/// topics surface — see build order step 10). Stored as the enum `name` so the
/// value survives the local→Supabase repository swap unchanged.
///
/// Note per CLAUDE.md: the audience may include under-18 users, so we collect
/// the minimum needed — a coarse band, never a date of birth or school name.
enum EducationLevel {
  highSchool('High school', 'Secondary / sixth form'),
  undergraduate('Undergraduate', 'Bachelor’s degree student'),
  postgraduate('Postgraduate', 'Master’s, MBA or doctoral'),
  earlyCareer('Early career', 'Working, new to derivatives'),
  other('Other', 'Self-taught or none of the above');

  const EducationLevel(this.label, this.description);

  /// Short name shown in pickers.
  final String label;

  /// One-line clarification shown under the label.
  final String description;

  static EducationLevel fromName(String? name) {
    return EducationLevel.values.firstWhere(
      (EducationLevel level) => level.name == name,
      orElse: () => EducationLevel.other,
    );
  }
}
