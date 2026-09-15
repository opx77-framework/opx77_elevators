# opx77_elevators — architecture

`opx77_elevators` pose une liste d'étages sur les ascenseurs natifs de Night City et ouvre ou
ferme chaque étage selon le métier que le personnage tient dans `opx77_core`. La moitié client
cherche les ascenseurs, lit le personnage et décide de ce qu'elle affiche ; la moitié serveur
adopte les ascenseurs, les verrouille et fait bouger la cabine après avoir revérifié tout ce
qu'elle peut prouver. La resource ne vérifie **pas** le métier côté serveur, ne persiste rien,
ne dessine aucune interface à elle (le panneau est celui d'`opx77_menu`) et ne cohabite pas avec
le paquet officiel `open77_elevators`. Le code est commenté en anglais, cette documentation est
en français ; le mode d'emploi (exports, commande, configuration, locales) est dans le
`README.md`.

## Manifeste

Les scripts partagés chargent d'abord : `config.lua`, `shared/text.lua`, `shared/locale.lua`,
puis les deux catalogues `locales/en.lua` et `locales/fr.lua` juste après le module de locale,
pour qu'aucun fichier plus bas n'appelle `locale()` contre un catalogue vide ; enfin
`shared/access.lua`, la porte, que les deux moitiés lisent. Côté serveur, `server/main.lua`
seul. Côté client, `client/state.lua` crée `OpxElevators.State` avant `client/main.lua`
(`OpxElevators.Runtime`), puis `client/panel.lua` (`OpxElevators.Panel`), et
`client/exports.lua` en dernier : publier la surface revient à affirmer qu'elle existe.

`reload_policy "local"` : la resource n'a pas de surface CEF, et le serveur ré-adopte chaque
ascenseur dès le prochain signalement d'un client (voir « Adopter sur signalement »).

- `network.events` — les signalements et les demandes d'étage vers le serveur, `bound`,
  `released`, `answer`, les lignes de chat et la suggestion de commande vers les clients.
- `world.elevators` — adopter un ascenseur natif, le verrouiller et déplacer la cabine.
- `elevators.read` — `Open77.elevators.nearby`, `all` et `get` : lire les ascenseurs natifs.
- `acl.read` — côté serveur, `Open77.acl.isAllowed`, pour ne suggérer la commande de diagnostic
  qu'à un joueur que l'ACL laisserait l'exécuter. Lecture seule.

Aucune `dependency` n'est déclarée : `opx77_core` et `opx77_menu` sont optionnels. Sans le
premier, les étages publics restent ouverts et les étages gardés se ferment ; sans le second,
`openPanel` répond `menu_not_running` et le reste fonctionne.

## Contrats

- **Six exports client** (`floors`, `isFloorAllowed`, `requestFloor`, `openPanel`,
  `nearestElevator`, `state`), qui répondent toujours une table portant `ok` et ne lèvent
  jamais. Les codes `error` sont listés dans `std/types.lua` (`ElevatorError`).
- **L'appelant est désigné par l'hôte.** `caller()` lit `GetInvokingResource()` et refuse
  `export_call_required` quand il n'y a pas de resource appelante : un appel sans appelant vient
  de l'intérieur de cette VM, qui s'est trompée de chemin (`OpxElevators.Runtime` et
  `OpxElevators.Panel` sont là pour elle). `requestFloor` inscrit ce nom comme `source` de
  l'événement.
- **`ok = true` sur `requestFloor` et `openPanel` veut dire « demandé »** : le verdict du serveur
  arrive sur l'événement local `OPX_ELEVATORS_CONFIG.EVENT` (`opx77:elevators`), avec `source`
  à `server`, `panel` ou le nom de la resource appelante ; un refus local y est publié aussi.
- **Les événements réseau** `opx77_elevators:sighted` et `opx77_elevators:request` entrent,
  `opx77_elevators:bound`, `:released` et `:answer` sortent ; `source` vient toujours de la
  connexion authentifiée, jamais de la charge utile.
- **La durée de vie d'un identifiant** : l'identifiant Open77 d'un ascenseur change à chaque
  redémarrage ; le nom durable d'un ascenseur est sa clé dans `config.lua`.

## Le métier est un indice côté client

Le runtime serveur d'Open77 n'a pas de bus d'événements inter-resources : la moitié serveur ne
peut pas demander un métier à `opx77_core` et ne peut donc pas refaire la vérification. Elle
refait tout le reste — l'ascenseur, l'étage, la position et le bucket du joueur, la cadence — et
`OpxElevators.Server.Request` ne contient aucune clause de métier. Les codes de métier
(`no_character`, `job_stale`, `job_required`, `grade_too_low`, `off_duty`) sont décidés sur le
client et restent des indices.

- **L'instantané** (`OpxElevators.State.snapshot`) ne garde que `job` et `jobs` du `PlayerData`,
  horodatés. Il est renouvelé à chaque `opx77:client:onPlayerLoaded` et
  `opx77:client:playerDataChanged` — une promotion change les étages à l'instant — et relu toutes
  les `POLL_MS` par `pull` : le cœur peut encore démarrer, la boucle redemande simplement.
- **Refusé n'est pas injoignable.** `OpxElevators.Runtime.Call` rend en troisième valeur si la
  cible a répondu : un refus du cœur veut dire « pas de personnage », et la porte se ferme tout de
  suite (`State.Forget`) au lieu d'attendre que l'instantané vieillisse ; un appel qui n'a jamais
  abouti laisse l'instantané vieillir.
- **Un appel d'export est vérifié à trois niveaux** : non envoyé, erreur d'appel, refus. La
  promesse de l'hôte est un userdata, testée par présence et jamais par type ; `await` cède la
  main et céder sous un `pcall` n'est pas sûr, donc seul le lancement est enveloppé. `pull` cède
  pour la même raison et tourne dans un thread à lui plutôt que sous le `pcall` de la boucle.
- **Un étage public reste ouvert sans instantané** (`OpxElevators.Access.Evaluate`) : une panne
  du cœur ne doit pas enfermer un hall. Un étage gardé se ferme au-delà de `JOB_MAX_AGE_MS`.
- **L'âge se mesure avec `FiniteNumber`, jamais `Coordinate`** : une horloge en millisecondes
  dépasse `BOUND` en cours de session.
- **Le refus nomme le plus proche.** `RANK` classe `off_duty` au-dessus de `grade_too_low`,
  lui-même au-dessus de `job_required`, pour qu'un refus dise le quasi-succès le plus proche plutôt
  que le premier que `pairs` rencontre.
- **Le service ne vit que sur le métier principal** : la table des appartenances porte des grades,
  pas une pointeuse. `MEMBERSHIP = "any"` fait compter les appartenances pour le grade, jamais pour
  `ON_DUTY`.

## Une gaine, un panneau

Une distance se mesure **au sol**, en X et Y, contre la position **déclarée** dans `config.lua` ;
Z est validé puis ignoré. Un ascenseur s'appelle donc depuis chaque étage de sa propre gaine, et un
personnage au douzième est aussi près du panneau qu'un autre dans le hall. `MATCH_RADIUS` décide
quelle gaine est un ascenseur natif, `USE_RADIUS` si le joueur peut utiliser le panneau, sur les
deux moitiés. Côté serveur, la cabine peut être en haut de la gaine : c'est la position déclarée
qui compte, jamais celle de la cabine.

- `POSITIONS` et `ENTITY_HASHES` sont construits une fois au chargement : `Locate` parcourt chaque
  ascenseur pour chaque ascenseur natif de chaque scan, et une coordonnée convertie là le serait à
  chaque fois.
- Les trois rayons et `JOB_MAX_AGE_MS` sont lus une fois au chargement, et une valeur que
  `Problems` refuse vaut zéro : une mauvaise valeur devient un avertissement au démarrage plutôt
  qu'une levée dans un gestionnaire réseau ou une export, qui doit répondre.
- `Locate` : un `ENTITY` déclaré désigne l'ascenseur, X et Y doivent quand même concorder ; un
  signalement dont un axe est cassé est un signalement cassé. À distance égale, la clé départage :
  l'ordre de `pairs` ne doit pas choisir entre deux gaines d'un même hall. `State.Nearest` applique
  la même règle.
- Un étage se désigne par son **index natif**, jamais par sa place dans `FLOORS` ; chaque entrée
  est contrôlée comme table, car `FLOORS = { 0, 1 }` est une configuration qu'on écrit.
- Côté client, la portée (`reach`) est mesurée au sol vers la position déclarée, comme le serveur.
  Si l'hôte ne donne pas la position du joueur (avant que le monde soit prêt, ou un NaN), le client
  retombe sur la distance 3D de l'hôte à la cabine, qui mesure autre chose : il peut offrir le
  panneau jusqu'à `MATCH_RADIUS` plus loin que ce que le serveur accepte, et le refuser à un étage
  où la cabine n'est pas. La réponse du serveur est celle qui compte.
- Un signalement est cru pendant deux scans (`STALE_MS`), pour qu'un passage manqué ne ferme pas
  un panneau ; `State.seen` garde un ascenseur dont le joueur s'est éloigné, et `Report` ne compte
  que les courants.

## Adopter sur signalement

Le serveur ne voit pas les ascenseurs natifs ; un client les voit. `scan` signale au serveur, au
plus toutes les `SIGHT_RETRY_MS`, chaque ascenseur configuré à portée qui n'est ni géré ni lié. La
topologie arrive de façon asynchrone : un ascenseur dont l'inspection n'a pas répondu
(`floorCount` ou `activeFloor` absents) attend le scan suivant. L'`id` d'une entrée de `nearby`
est celui du serveur et n'existe qu'une fois l'ascenseur géré. `Open77.elevators` manque sur un
client sans monde chargé ou sur une version du jeu antérieure à l'API des ascenseurs : le client
le journalise une fois et ne scanne pas. La boucle de scan tourne sous `pcall`, car une levée d'un
appel hôte dans un `CreateThread` nu terminerait le scan pour toute la session.

Le serveur choisit lui-même l'ascenseur, le bucket et le nombre d'étages (`opx77_elevators:sighted`) :

- Le hash moteur doit avoir la forme `0x` + 16 chiffres hexadécimaux. Un rejet est dit **une
  fois** (`warnedEntity`) : un désaccord de format sur le fil ne se verrait sinon que comme
  `not_adopted` pour toujours. Les identifiants moteur sont opaques : comparés en chaînes minuscules
  (`sameEntity`), jamais à travers `tonumber`.
- Le signalement n'est cru que dans `SCAN_RADIUS` de la position du joueur lue par le serveur.
- **Le bucket est celui de l'ascenseur**, jamais celui du joueur qui signale : sinon le premier
  passant fixerait l'ascenseur dans son propre bucket pour la vie du processus. Un ascenseur dans un
  bucket est invisible aux joueurs hors de ce bucket.
- **Le nombre d'étages aussi** : il devient le plafond contre lequel chaque index est vérifié. Un
  écart entre le client et `FLOOR_COUNT` est journalisé une fois par ascenseur (`warnedCount`).

`OpxElevators.Server.Adopt` répond une valeur et ne lève jamais. `Open77.elevators.all` est un
appel hôte, et une levée depuis un gestionnaire réseau est avalée en silence : sa réponse est
contrôlée comme table. `adopt` est enveloppé dans un `pcall` parce qu'il n'est pas documenté qu'il
ne lève pas. Un ascenseur déjà tenu par l'hôte est **ré-réclamé** (après un redémarrage de cette
resource), à trois conditions : le hash vient du fil, donc l'ascenseur doit se trouver à la
position de la clé (`wrong_place`, sinon le hash d'un autre ascenseur ferait pointer cette clé vers
cette cabine) ; il ne doit pas déjà être lié à une autre clé (`already_owned`) ; et il est
reverrouillé, car le drapeau n'a pas survécu au redémarrage et `adopt` ne repasse pas. L'hôte
imbrique la position sous `position` dans une forme et l'aplatit dans l'autre (`atElevator`).

`owned` est l'index de ce que la resource a adopté ; `Open77.elevators.all` reste l'autorité.
`told` retient quels joueurs ont reçu l'identifiant d'une clé, pour qu'un retrait
(`release`) les atteigne tous ; la journalisation d'un retrait appartient à l'appelant. Le compte
d'étages envoyé dans `bound` est relu dans l'enregistrement, que `Adopt` a réglé entre la
configuration et l'hôte. Un refus d'adoption est journalisé au plus une fois par seconde par
joueur (`logWindows`) : un client signale plus vite qu'un disque n'écrit.

## Le verrou : cette resource est la seule à bouger la cabine

`applyLock` pose le drapeau `locked` de l'hôte sur chaque ascenseur adopté, en gardant les autres
drapeaux (`powered` reste tel que l'hôte l'a mis). L'autorité des ascenseurs refuse alors une demande
envoyée directement par un client. Un verrou qui échoue donne une ligne, pas un retour arrière : un
ascenseur non verrouillé répond aussi directement à un client.

Au démarrage, `server/main.lua` vérifie dans un thread, et non au niveau fichier, si
`open77_elevators` tourne aussi : au chargement, une resource listée après celle-ci est encore
`discovered`. La plateforme refuse un propriétaire différent, donc celle qui démarre en premier
tient la cabine.

## Une demande d'étage

`OpxElevators.Runtime.Use` vérifie d'abord localement (`Check`), puis l'identifiant : la liaison du
serveur de cette resource gagne sur un scan, car `nearby` signale aussi les ascenseurs adoptés par
d'autres. Sans identifiant (vu mais pas encore adopté), la demande est refusée `not_adopted` sans
partir.

`OpxElevators.Server.Request` revérifie, dans l'ordre : la cadence (`REQUESTS_PER_WINDOW` par
`REQUEST_WINDOW_MS`), l'ascenseur, l'étage, l'adoption, le nombre d'étages natif, la position, le
bucket, la portée au sol. Un ascenseur que l'hôte ne connaît plus est **libéré**, pas seulement
oublié : un client qui garderait l'identifiant mort ne resignalerait jamais l'ascenseur.

- `within` s'arrête **à** la limite plutôt que de compter pendant toute la fenêtre.
- La limite gouverne la cabine, pas la réponse : `answer` n'est retenu que quand la limite est la
  raison du refus. Un refus est journalisé au plus une fois par seconde par joueur, car le chemin du
  refus est le moins coûteux pour un attaquant.
- Toute valeur venue du fil passe par `safe` (`OpxElevators.Text.Clean`, 64 caractères, caractères
  de contrôle remplacés) avant une chaîne de format : un saut de ligne y forgerait une ligne de
  journal entière. `Text.Span` mesure en caractères UTF-8 et borne son parcours à `maximum * 4`
  octets, car une suite d'octets de continuation ne commence aucun caractère. Les motifs Lua
  travaillent en octets : `#value` compte des octets et `maximum` des caractères, donc un texte
  qui a moins d'octets que `maximum` n'a pas besoin d'être mesuré.

## Départs et balayage

`onPlayerDisconnected` est le départ d'un joueur **admis** ; une connexion refusée à la porte lève
`onPlayerRejected`, que cette resource n'a aucune raison d'écouter. Son `reason` vaut
`connection_closed` ou le texte d'une déconnexion, d'une expulsion ou d'un bannissement.
`OpxElevators.Server.Forget` efface les fenêtres du joueur et ses audiences.

**Une cabine laissée en mouvement est rappelée.** `Request` retient le passager (`rider`) et la fin
du trajet (`rideEndsAtMs`) ; un départ pendant le trajet renvoie la cabine à l'étage 0, que chaque
ascenseur configuré possède et qu'aucun ne garde, plutôt que de la laisser arriver et se garer
ouverte sur un étage gardé dont personne ne répond.

Le balayage (`CreateThread`, toutes les 60 s, sous `pcall` : une levée d'un appel hôte y
terminerait le balayage pour la vie du processus) fait deux choses :

- Une adoption qui n'a jamais bougé de cabine en `UNUSED_MS` (10 min) est libérée : le hash d'un
  signalement ne peut pas être vérifié avant l'adoption, et une clé liée par un faux signalement doit
  guérir. Une adoption qui a servi (`usedAtMs`) est laissée tranquille. Une ré-réclamation porte
  `atMs` pour la même raison : sans lui, le calcul `at - at` ne dépassait jamais le seuil, et une clé
  ré-réclamée après un redémarrage — précisément le cas où le hash est venu du fil sans vérification
  — ne guérissait jamais.
- Les fenêtres de cadence plus vieilles que `WINDOW_GC_MS` sont ramassées, les quatre tables
  (signalements, demandes, lignes de journal, suggestions) ensemble. `within` crée une fenêtre
  à la demande : un paquet arrivé après le départ d'un joueur recréait l'entrée que `Forget` venait
  d'effacer, et plus rien ne l'effaçait ; un identifiant de joueur recyclé héritait du compteur.
  `WINDOW_GC_MS` est bien plus long que la plus large fenêtre demandée, donc le compteur d'un joueur
  présent n'est jamais perdu.

## Horloge

`nowMs` lit l'horloge monotone de l'hôte (`Open77.time.monotonic` répond en **secondes**). Une
lecture non finie est écartée : un NaN n'expirerait rien, un infini tout. Côté serveur, une lecture
qui échoue retombe sur `GetGameTimer`, la même horloge d'ordonnanceur déjà en millisecondes, avec un
avertissement unique : garder la dernière lecture n'est pas une dégradation sûre, car toutes les
échéances du fichier partagent cette horloge, et une horloge figée saturerait chaque fenêtre de
cadence pour de bon et arrêterait le balayage. Le client garde sa dernière lecture (voir « Limites
connues »).

## Configuration et diagnostic

`OpxElevators.Access.Problems` liste tout ce qui ne va pas dans la configuration sans avoir besoin
du monde, trié. Elle ne peut pas vérifier un **nom** de métier : ils vivent dans `opx77_core`, que
cette VM ne peut pas interroger. Les axes sont vérifiés en premier, car chaque distance et chaque
`%.2f` lève sur une chaîne ; `FLOOR_COUNT` a son propre test, car `%d` lève sur un nombre sans forme
entière (`Integer`, dans `BOUND`) ; un trou dans `FLOORS` arrive là comme `nil` et est contrôlé
avant toute lecture ; un `INDEX` invalide est oublié aussitôt, car `seen[nil]` lèverait sur la
valeur même qu'on vient de diagnostiquer. `List` saute une entrée malformée plutôt que de la
dessiner : c'est `Problems` qui la signale. `ELEVATORS` absent se lit comme une table vide, car
chaque lecture est atteignable depuis une export.

Les problèmes sont dits au démarrage et à la demande : chacun produit le même symptôme, un bouton
mort. La commande de diagnostic est restreinte (elle imprime des positions et l'état d'adoption,
information d'opérateur) ; son rapport est trié, car l'ordre de `pairs` le remanierait d'une
exécution à l'autre. Il reste du texte : imprimé à la console et envoyé à un joueur comme lignes de
chat par `chat:addMessage`, jamais par `open77:command:result`, dont `opx77_chat` n'imprime pas les
réponses acceptées. La suggestion (`chat:ready`, un événement réseau qu'un client peut envoyer aussi
vite qu'il veut) est limitée à une par `SUGGEST_EVERY_MS` par joueur, n'est envoyée qu'à un joueur
que l'ACL autorise — `permitted` répond faux, jamais nil, sans lecteur d'ACL — et liste les clés
triées.

## Le panneau

`client/panel.lua` dessine la liste par `opx77_menu`, optionnel : un menu absent coûte une ligne de
journal. Un étage refusé porte sa raison comme valeur de ligne — une ligne grisée sans rien à côté se
lit comme cassée — : le `REASON` de l'opérateur s'il existe, sinon `elevators.locked`. Les
`LABEL` et `REASON` de `config.lua` sont les mots de l'opérateur et ne sont jamais traduits.

La sélection d'une ligne rend la table `data` posée sur l'élément, telle quelle. Un refus est
affiché sous la liste (`setStatus`), au mieux : la liste s'est déjà fermée à la sélection. Il ne l'est
que pour un panneau ouvert par ce fichier (`openFor`), et une seule fois, car n'importe quelle
resource peut lever le nom de l'événement ; c'est la réponse qui efface `openFor`, pas la sélection.

## Invariants de la plateforme

- **Une resource ne touche pas aux entrailles d'une autre** : `opx77_core` et `opx77_menu` ne sont
  joints que par leurs exports, et leur absence est une dégradation.
- **Un pouvoir de staff exige une autorisation ACL côté serveur** : la commande de diagnostic est
  restreinte et résolue par l'hôte ; la suggestion n'est qu'un affichage.
- **L'identité d'une entité vit dans un registre serveur** : un ascenseur est désigné par sa clé de
  configuration et l'identifiant que l'hôte a donné à l'adoption, jamais par ce qu'un client envoie ;
  le bucket et le nombre d'étages viennent de la configuration.
- **Un appel d'export est vérifié à trois niveaux**, et `await` n'est jamais appelé sous un `pcall`.

## Journal et textes

Tout texte montré à un joueur vient d'un catalogue ; les journaux, le rapport de la commande et les
codes d'erreur restent en anglais. `OpxElevators.Locale.Set` est appliqué au chargement de
`shared/locale.lua`, sinon `LOCALE` serait inerte ; un code inconnu est accepté et retombe sur `en`,
car les catalogues s'enregistrent après ce fichier. `OpxElevators.Locale.register` garde son nom en
minuscules : les fichiers de traduction des opérateurs l'appellent.

## Clés résolues à l'exécution

- `REFUSAL[code]` dans `client/panel.lua` : les clés `elevators.noElevatorNearby` à
  `elevators.tooFar` sont choisies d'après le code de refus ; un code sans entrée lit
  `elevators.refused`.

## Limites connues

- **L'horloge client garde sa dernière lecture** au lieu de retomber sur `GetGameTimer` : figée,
  elle ne relit plus le cœur et ne fait plus vieillir ni l'instantané ni les signalements.
- **`POLL_MS`, `SCAN_MS`, `TRAVEL_MS`, `REQUEST_WINDOW_MS` et `REQUESTS_PER_WINDOW` sont lus bruts**
  alors que le README dit qu'une valeur invalide est lue comme zéro : une chaîne y lève (à chaque
  scan côté client, dans le gestionnaire de demande côté serveur).
- **`openFor` n'est pas effacé par une réponse acceptée** : un refus ultérieur venu d'un autre
  appelant peut encore s'afficher sous un panneau déjà fermé.
