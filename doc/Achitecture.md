## 📄 **Une architecture Event-Driven pour ECS : Réconcilier performance et modularité**

---

### Introduction

Le développement de moteurs de jeu est souvent perçu comme un domaine réservé à une élite technique. Pourtant, au cœur de chaque moteur performant se trouve une composante essentielle : **l’architecture logicielle**.

Une mauvaise architecture conduit inévitablement à une dette technique. Une bonne, au contraire, garantit **pérennité**, **modularité** et **maintenabilité**. Parmi les modèles dominants, le paradigme **Entity-Component-System (ECS)** s’impose. Toutefois, il n’est pas exempt de limitations.

Dans cet article, je propose une variante hybride : l’**Event-Driven ECS (EDECS)**. Cette architecture conserve les principes fondamentaux de l’ECS tout en introduisant un modèle **réactif**, basé sur le besoin des systèmes, pour fluidifier la communication et améliorer le traitement des entités.

> ⚠️ À ne pas confondre avec un Event Bus ou un système pub/sub : ici, le terme "Event-Driven" désigne un **dispatch conditionnel et structuré**, basé sur les abonnements des systèmes aux combinaisons de composants.

---

### Qu’est-ce que l’ECS ?

L’**Entity-Component-System (ECS)** est une architecture dans laquelle les objets du jeu sont représentés par des **entités**, identifiées de manière unique. Ces entités sont **structurelles** : elles ne possèdent ni comportement ni logique.

La logique du jeu est portée par des **systèmes**, qui opèrent sur les **composants** attachés aux entités. Chaque système traite uniquement les entités possédant un ensemble précis de composants.

Les ECS modernes utilisent souvent la notion d’**archetypes** : des regroupements d’entités partageant la même combinaison de composants, facilitant un traitement batché et optimisé.

---

### Représentation par bitsets

Une approche classique consiste à représenter les archetypes par des bitsets. Cela permet des vérifications rapides via des opérations logiques :

```julia
archetype = 0b0011  # L'entité possède les composants 1 et 2
physic    = 0b0010  # Le système "Physic" requiert uniquement le composant 2

if (archetype & physic == physic)
    # L'entité est compatible avec le système Physic
end
```

Cette méthode est performante, mais peu évolutive à grande échelle (limites binaires, gestion complexe). On peut aussi recourir à des **requêtes dynamiques**, mais leur coût est non négligeable.

---

## Qu’est-ce qu’un Event-Driven ECS ?

L’**Event-Driven ECS (EDECS)** repose sur une architecture centralisée, où un **gestionnaire principal (`ECSManager`)** regroupe les entités par archetype.

Les systèmes **s’abonnent** aux archetypes qui les intéressent. À chaque tick, le gestionnaire **distribue (dispatch)** les entités correspondantes à chaque système.

Ce modèle repose sur trois piliers :

* un stockage structuré des entités,
* une distribution ciblée des données,
* un traitement réactif, orienté données.

---

### Exemple en Julia

```julia
using EDECS

# Définition des composants
struct Health <: AbstractComponent
    hp::Int
end

mutable struct TransformComponent <: AbstractComponent
    x::Float32
    y::Float32
end

struct PhysicComponent <: AbstractComponent
    velocity::Float32
end

# Aides pour nommer les composants
get_name(::TransformComponent) = :Transform
get_name(::PhysicComponent)    = :Physic

# Déclaration des systèmes via une macro
@system(PhysicSystem, Entity)
@system(PrintSystem, Entity)
@system(RenderSystem, Entity)

# Implémentation du traitement pour chaque système
function run!(::PhysicSystem, entities)
    for entity in entities
        t = entity.components[:Transform]
        v = entity.components[:Physic]
        t.x += v.velocity
    end
end

function run!(::PrintSystem, entities)
    for entity in entities
        println("Entity: $(entity.id)")
    end
end

function run!(::RenderSystem, entities)
    for entity in entities
        t = entity.components[:Transform]
        println("Rendering entity $(entity.id) at position ($(t.x), $(t.y))")
    end
end

# Initialisation du gestionnaire ECS
ecs = ECSManager{Entity}()

# Création de deux entités
e1 = Entity(1, Dict(:Health => Health(100), :Transform => TransformComponent(1.0, 2.0)))
e2 = Entity(2, Dict(:Health => Health(50), :Transform => TransformComponent(-5.0, 0.0), :Physic => PhysicComponent(1.0)))

add_entity!(ecs, e1)
add_entity!(ecs, e2)

# Initialisation des systèmes
print_sys   = PrintSystem()
physic_sys  = PhysicSystem()
render_sys  = RenderSystem()

# Abonnement aux archetypes
subscribe!(ecs, print_sys,   (:Health, :Transform))
subscribe!(ecs, physic_sys,  (:Transform, :Physic))
subscribe!(ecs, render_sys,  (:Transform,))

# Lancement des systèmes (en tâche asynchrone)
run_system!(print_sys)
run_system!(physic_sys)
run_system!(render_sys)

# Simulation de 3 frames
for i in 1:3
    println("FRAME $i")
    dispatch_data(ecs)
    yield()
end
```

---

## Benchmark de l’EDECS

Ici, nous mesurons uniquement les performances du **dispatch**, car c’est la fonction clé, indépendante de la logique métier.

**Configuration de test :**

* **Processeur** : Intel Pentium T4400 @ 2.2 GHz
* **RAM** : 2 Go DDR3
* **OS** : Windows 10
* **Julia** : v1.10.3
* **Threads actifs** : 2

**Scénario** :

* 3 composants (Health, Transform, Physic)
* 3 systèmes actifs
* Variation de la taille des chunks

| Nombre d’objets | 64 obj/chunk         | 128 obj/chunk       | 256 obj/chunk       | 512 obj/chunk       |
| --------------- | -------------------- | ------------------- | ------------------- | ------------------- |
| 128             | 0.031 ms (18 alloc)  | 0.032 ms (12 alloc) | 0.037 ms (6 alloc)  | 0.040 ms (6 alloc)  |
| 256             | 0.057 ms (30 alloc)  | 0.056 ms (18 alloc) | 0.040 ms (12 alloc) | 0.032 ms (6 alloc)  |
| 512             | 0.069 ms (54 alloc)  | 0.054 ms (30 alloc) | 0.053 ms (18 alloc) | 0.052 ms (12 alloc) |
| 1024            | 0.094 ms (102 alloc) | 0.059 ms (54 alloc) | 0.068 ms (30 alloc) | 0.046 ms (18 alloc) |

> ✅ **Analyse** :
>
> * Des chunks trop petits augmentent les allocations et dégradent la performance (découpage excessif).
> * Des chunks plus grands réduisent le coût du dispatch mais sont plus difficiles à paralléliser.
> * **Compromis efficace** : 128 à 256 objets par chunk.
> * **Astuce** : utiliser un système de **pooling** et fixer dynamiquement la taille des chunks selon la cible matérielle.

---

## Avantages d’un Event-Driven ECS

* **Performances stables** : un seul dispatch par tick, aucune redondance de requêtes.
* **Parallélisme facilité** : les chunks peuvent être traités sur plusieurs threads.
* **Extensibilité dynamique** : on peut ajouter ou retirer des systèmes à chaud.
* **Compatibilité réseau native** : un serveur peut servir de gestionnaire central, répartissant les entités entre les clients.
* **Localité mémoire améliorée** : le regroupement par archetype favorise le cache-friendly access.

---

## Conclusion

L’EDECS dépasse les limites classiques de l’ECS, en apportant une **meilleure scalabilité**, une **architecture réactive**, et une **meilleure préparation au traitement parallèle ou distribué**.

Ce modèle a été implémenté dans mon moteur expérimental en Julia. Il combine la simplicité de l’ECS avec la réactivité d’un dispatch ciblé, sans sacrifier les performances.

👉 Le code source sera publié prochainement. Pour toute question technique, n’hésitez pas à me contacter.

---