# Spec 008 : budget jamais bloquant, rayons fiables

## Problèmes
- Budget de 60 € : génération refusée (« Contraintes impossibles »), alors qu'avec 100 € l'IA produit une semaine à 47 €. Le modèle juge le budget trop bas et remplit `infeasible` malgré la consigne.
- Liste de courses : « Yaourt nature » rangé en fruits et légumes, rayon choisi par l'IA sans contrôle.

## Exigences
- FR-801 : un refus de l'IA motivé par le prix (budget, €, prix, coût, plafond, cher) n'est jamais montré comme bloquant. Nouvel essai avec la raison du refus et la consigne de proposer le planning le moins cher.
- FR-802 : second refus pour le budget : nouvel essai avec un budget annoncé doublé. Le coût obtenu est contrôlé avec le vrai budget ; dépassement signalé en avertissement (spec 004).
- FR-803 : les refus non liés au prix (allergies, temps) restent affichés tels quels.
- FR-804 : rayon déduit du nom quand un mot-clé ne laisse pas de doute (surgelé, conserve, crèmerie, viande et poisson, boulangerie), à la validation, à la construction de la liste et au lancement pour les listes enregistrées.
