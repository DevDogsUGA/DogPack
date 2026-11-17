const List<String> classYearValues = [
  'freshman',
  'sophomore',
  'junior',
  'senior',
  'graduate',
];

String? validateClassYear(String? input) {
  if (classYearValues.contains(input)) {
    return null;
  }
  return 'Choose a class year.';
}