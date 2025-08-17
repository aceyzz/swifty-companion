<img title="42_swifty-companion" alt="42_swifty-companion" src="./utils/banner.png" width="100%">

<br>

## Index

- [Consigne](#consigne)
- [Objectifs](#objectifs)
- [Architecture de l’application](#architecture-de-lapplication)
- [Fonctionnalités](#fonctionnalités)
- [Gestion des erreurs](#gestion-des-erreurs)
- [Bonus](#bonus)
- [Soumission](#soumission)

<br>

## Consigne

Le projet **Swifty Companion** a pour but de vous initier au développement d’applications mobiles.  
Il consiste à créer une application qui permet de récupérer et d’afficher les informations des étudiants de 42 via l’API officielle.

- L’application doit comporter **au moins deux vues** :  
	• Une vue d’accueil avec un champ de recherche (login 42).  
	• Une vue de profil étudiant avec les informations détaillées.  
- L’application doit utiliser **OAuth2 avec l’API 42** (intra).  
- La mise en page doit être **moderne et adaptable** à différentes tailles d’écran.  
- Le code doit être versionné correctement et sans divulgation de secrets (`.env` obligatoire pour les clés API).  
- Le projet sera évalué uniquement par des humains, lors de la soutenance.  

<br>

## Objectifs

Ce projet vous permettra de vous familiariser avec :

- Un **langage de programmation mobile** (Swift, Kotlin, Dart, Java, etc.)  
- Un **IDE moderne** (Xcode, Android Studio, ou équivalent)  
- L’usage d’un **framework mobile** (ex. Flutter, SwiftUI, Jetpack Compose)  
- La consommation d’une **API REST** (API 42) avec gestion d’authentification OAuth2  
- Les bonnes pratiques de sécurité pour le stockage des secrets (`.env` ignoré par Git)  

<br>

## Architecture de l’application

<table>
	<tr>
		<td align="center" valign="middle"><strong>1. Home</strong></td>
		<td>
			Page d'accueil de l'application.<br/>
			- Présentation de l'application<br/>
			- Accès rapide aux principales fonctionnalités
		</td>
	</tr>
	<tr>
		<td align="center" valign="middle"><strong>2. Search</strong></td>
		<td>
			Rechercher un étudiant 42 et afficher son profil.<br/>
			- Champ de recherche pour le login 42<br/>
			- Affichage détaillé du profil de l'étudiant recherché<br/>
			- Gestion des erreurs (login inexistant, API indisponible, etc.)
		</td>
	</tr>
	<tr>
		<td align="center" valign="middle"><strong>3. MyProfile</strong></td>
		<td>
			Voir le profil de l'utilisateur connecté.<br/>
			- Informations personnelles (login, email, niveau, wallet, etc.)<br/>
			- Photo de profil<br/>
			- Liste des compétences et projets réalisés
		</td>
	</tr>
	<tr>
		<td align="center" valign="middle"><strong>4. Settings</strong></td>
		<td>
			Réglages de l'application.<br/>
			- Gestion des préférences utilisateur<br/>
			- Options de sécurité et de confidentialité<br/>
			- Déconnexion
		</td>
	</tr>
</table>

<br>

## Fonctionnalités

- Authentification sécurisée via OAuth2 (token unique, pas un token par requête)  
- Recherche par login d’un étudiant 42  
- Affichage de la photo de profil  
- Affichage des compétences (skills + pourcentage de maîtrise)  
- Liste des projets réalisés (validés ou échoués)  
- Interface responsive adaptée à différentes tailles d’écran  
- Navigation entre les vues (accueil ↔ profil étudiant)  

<br>

## Gestion des erreurs

L’application doit prendre en compte tous les cas possibles :

- Login introuvable  
- Erreur réseau (connexion absente, serveur down)  
- Problème d’authentification OAuth2  
- Timeout ou API non disponible  

Les erreurs doivent être **affichées proprement** à l’utilisateur, sans crash.  

<br>

## Bonus

Des points bonus peuvent être obtenus si l’application :  

- Rafraîchit automatiquement le token OAuth2 à expiration  
- Gère la reconnexion automatique en cas de perte de réseau  

Le bonus n’est évalué que si la partie obligatoire est **parfaite et fonctionnelle**.  

<br>

## Soumission

- Le rendu se fait **dans le dépôt Git** comme d’habitude.  
- Seuls les fichiers présents dans ce dépôt seront évalués.  
- Vérifiez soigneusement le nom de vos fichiers et dossiers.  
- Les credentials/API keys doivent être dans un **`.env` ignoré par Git**.  
