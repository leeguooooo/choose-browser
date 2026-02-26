# Dependency Boundaries

Task 1 enforces a one-way dependency direction in code organization:

- `UI` depends on `Routing`
- `Routing` depends on `Execution`, `Discovery`, and `Store`
- `Core` owns shared models and protocols used by all feature modules

To keep the bootstrap build-safe and minimal, all modules compile in one target for now. Later tasks may split these folders into framework targets while preserving this direction.
