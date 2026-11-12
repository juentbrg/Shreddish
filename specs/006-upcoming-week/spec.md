# Feature Specification: Planifier une semaine à venir

**Feature Branch**: `006-upcoming-week`

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: « Pouvoir programmer une semaine ultérieure : on est jeudi, j'aimerais planifier à
partir de dimanche prochain. »

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choisir le premier jour (Priority: P1)

« Planifier une semaine » ouvre un choix du premier jour : aujourd'hui, demain, lundi prochain, dimanche
prochain, lendemain du planning actuel, ou une date jusqu'à J+13.

**Acceptance Scenarios**:

1. **Given** semaine en cours du jeudi 12 au mercredi 18, **When** planification à partir du dimanche 15,
   **Then** la semaine en cours garde jeudi à samedi, la nouvelle couvre dimanche 15 au samedi 21.
2. **Given** planification à partir d'aujourd'hui, **When** génération, **Then** le planning actuel passe en
   historique, intact (journal conservé), comme avant.
3. **Given** deux plannings actifs, **When** onglet Semaine, **Then** bascule « En cours » / « À venir » ;
   Journal sur la semaine du jour ; Courses sur la semaine à venir par défaut, avec la même bascule.

## Requirements *(mandatory)*

- **FR-501**: Premier jour entre aujourd'hui et J+13.
- **FR-502**: Semaine future : plannings actifs commençant le même jour ou après → historique ; chevauchants →
  jours à partir du premier jour remplacés, liste de courses reconstruite ; terminés avant aujourd'hui → historique.
- **FR-503**: Semaine démarrant aujourd'hui : plannings actifs → historique, sans suppression.
- **FR-504**: Plusieurs plannings actifs (au plus deux en pratique), sans changement de schéma (`isCurrent`).
