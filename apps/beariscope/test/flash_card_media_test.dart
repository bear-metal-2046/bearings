import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/study/flash_card_media.dart';
import 'package:beariscope/widgets/team_avatar.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';

void main() {
  test('flash cards choose an event per team and media type', () {
    const sharedPhoto = CompetitionMedia(
      id: 'shared',
      type: 'imgur',
      foreignKey: 'shared',
      rosterMedia: true,
      preferred: false,
      teams: [EntityRef('frc2046'), EntityRef('frc254')],
      directUrl: 'https://example.com/shared.jpg',
      details: MediaDetails(),
    );
    const olderAvatar = CompetitionMedia(
      id: 'avatar',
      type: 'avatar',
      foreignKey: 'avatar',
      rosterMedia: true,
      preferred: true,
      teams: [EntityRef('frc2046')],
      details: MediaDetails(avatarBase64: 'AA=='),
    );
    const newerPhoto = CompetitionMedia(
      id: 'new',
      type: 'imgur',
      foreignKey: 'new',
      rosterMedia: true,
      preferred: true,
      teams: [EntityRef('frc2046')],
      directUrl: ' https://example.com/new.jpg ',
      details: MediaDetails(),
    );

    final media = combineFlashCardMedia({
      '2026test': [sharedPhoto, olderAvatar],
      '2027test': [
        newerPhoto,
        const CompetitionMedia(
          id: 'invalid',
          type: 'avatar',
          foreignKey: 'invalid',
          rosterMedia: true,
          preferred: true,
          teams: [EntityRef('frc2046')],
          details: MediaDetails(avatarBase64: 'invalid!'),
        ),
      ],
    });

    expect(media['frc2046'], [newerPhoto, olderAvatar]);
    expect(media['frc254'], [sharedPhoto]);
    expect(flashCardPhoto(media['frc2046']!), 'https://example.com/new.jpg');
    expect(flashCardPhoto(media['frc254']!), 'https://example.com/shared.jpg');
    expect(
      teamAvatarImages(media['frc2046']!, 'frc2046').single,
      isA<MemoryImage>(),
    );
  });
}
