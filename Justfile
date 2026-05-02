# =============================================================================
# Justfile — Task Runner
# Responsabilidad: lanzar scripts del repositorio desde la raíz.
# NO construye ni empaqueta. Para eso usar: make
# =============================================================================

import 'just/install.just'

# Listar todas las tareas disponibles
default:
    @just --list --unsorted
