class FlashCardOptions {
  const FlashCardOptions({
    this.nameFirst = false,
    this.shuffled = false,
    this.showPhotos = true,
  });

  final bool nameFirst;
  final bool shuffled;
  final bool showPhotos;

  FlashCardOptions copyWith({
    bool? nameFirst,
    bool? shuffled,
    bool? showPhotos,
  }) => FlashCardOptions(
    nameFirst: nameFirst ?? this.nameFirst,
    shuffled: shuffled ?? this.shuffled,
    showPhotos: showPhotos ?? this.showPhotos,
  );
}
