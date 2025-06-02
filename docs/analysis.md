

# Études préliminaires

## Analyse du problème

Montréal dispose d’un réseau de transport en commun relativement efficace au centre-ville, mais de nombreuses zones périphériques souffrent d’un accès limité et inefficace au réseau principal. Par exemple, dans l’arrondissement d’Anjou, il existe très peu d’options rapides pour rejoindre la ligne bleue du métro. Les usagers doivent compter sur un nombre restreint de bus, souvent ralentis par la circulation ou des travaux, avec des fréquences peu adaptées aux heures de pointe.
Ce manque d’alternatives flexibles oblige de nombreux citoyens à composer eux-mêmes leurs trajets en combinant plusieurs modes de transport : par exemple, conduire jusqu’à une station de métro, puis prendre le métro ou un vélo BIXI. Toutefois, aucune application actuelle ne permet de planifier efficacement un trajet multimodal adapté aux conditions réelles (fréquences, stationnements disponibles, présence de BIXI, etc.). Cela engendre un stress logistique, une perte de temps considérable, et une sous-utilisation des options de mobilité durable.
## Exigences

Exigences fonctionnelles
L’application doit permettre à un utilisateur de planifier un trajet combinant plusieurs modes de transport (voiture, métro, bus, vélo, marche).
L’utilisateur doit pouvoir choisir les types de transport qu’il souhaite utiliser.
L’application doit afficher les horaires (même si dans ce projet, ils seront statiques).
Les stations BIXI et les stationnements incitatifs doivent être intégrés dans le planificateur.
L’utilisateur doit pouvoir choisir un critère d’optimisation (temps, coût, empreinte carbone).
Des points de transition multimodaux doivent être suggérés automatiquement selon la position de départ.

Exigences non fonctionnelles
L’interface de l’application doit être intuitive et conviviale.
Le temps de calcul d’un itinéraire doit être inférieur à 5 secondes.
Le système doit être scalable pour d’éventuelles données en temps réel (dans une version future).
L’application doit être compatible avec les appareils iOS.
La majorité des calculs doivent être effectués localement sur l’appareil de l’utilisateur.
## Recherche de solutions

Google Maps et Apple Maps proposent une planification unimodale avec la possibilité de sélectionner un seul mode de transport à la fois.
Transit est une application montréalaise qui suit les autobus en temps réel et prévoit leur position sur le réseau STM.
Chrono, développée par l’ARTM, permet de suivre les horaires et trajets des services comme la STM, STL, RTL et REM, mais sans planification intermodale avancée.
## Méthodologie
1. Analyse des besoins
Identifier les modes de transport à prendre en charge (voiture, marche, bus, métro, vélo).
Déterminer les contraintes : distance maximale à pied, préférences utilisateur, points de transition.
Répertorier les types de transitions intermodales possibles (ex. : stationnement → métro).

2. Modélisation et intégration des données
Télécharger et analyser les données GTFS statiques (STM, REM, BIXI).
Construire un graphe pondéré représentant les trajets possibles entre arrêts et stations.
Ajouter les stations BIXI comme points de départ ou d’arrivée pour les segments vélo.
3. Développement du backend (Go)
Créer un serveur HTTP avec l’API REST en utilisant le framework Gin.
Implémenter un moteur de planification basé sur l’algorithme A* ou Dijkstra.
Exposer un endpoint /route recevant les requêtes de l’app mobile et retournant les itinéraires proposés.
4. Développement de l’application iOS (Swift)
Concevoir une interface simple permettant à l’utilisateur d’entrer un point de départ et une destination.
Utiliser MapKit ou Mapbox pour afficher les trajets et les étapes intermodales.
Consommer l’API REST du backend et afficher les résultats de manière claire.
5. Tests et validation
Vérifier le fonctionnement complet du système, de l’envoi de la requête à l’affichage du trajet.
Tester différents scénarios (trajets intermodaux, trajets en périphérie, trajets simples).
Comparer les itinéraires proposés à ceux de Google Maps ou Apple Maps pour valider la pertinence du planificateur.
Outils
Backend : développé en Go pour sa simplicité, sa performance et sa gestion efficace de la concurrence.
Framework : Gin, un web framework Go léger et performant pour créer des APIs RESTful.
Frontend mobile : développé en Swift, le langage recommandé par Apple pour les applications iOS.
Données :
GTFS STM et REM (statique)
Stations BIXI (station_information.json, statique)
Cartographie : Mapbox, pour ses capacités de personnalisation avancées et son modèle gratuit jusqu’à 50 000 chargements/mois.
Tests
Tests fonctionnels
Validation des itinéraires multimodaux selon divers scénarios (voiture + métro, marche + BIXI, etc.).
Vérification de la robustesse du moteur de planification (résistance aux erreurs, cohérence des résultats).
Mesure du temps de calcul (< 5 secondes).
Évaluation de la consommation mémoire et des performances du graphe en fonction de sa taille.
Tests d’utilisabilité
Tests utilisateurs avec des profils variés (étudiants, travailleurs en périphérie).
Collecte de retours qualitatifs sur la clarté de l’interface, la pertinence des suggestions, la lisibilité des étapes.
Ajustements itératifs basés sur les commentaires (UX/UI).