# Python -- Combined References

## Language and Standard Library

- https://docs.python.org/3.12/reference/index.html -- Language Reference
- https://docs.python.org/3.12/library/index.html -- Standard Library
- https://docs.python.org/3.12/library/typing.html -- typing module (use sparingly -- prefer built-ins)
- https://docs.python.org/3.12/library/dataclasses.html -- @dataclass
- https://docs.python.org/3.12/library/functools.html -- functools (cached_property, wraps, reduce)
- https://docs.python.org/3.12/library/contextlib.html -- contextmanager, suppress, asynccontextmanager
- https://docs.python.org/3.12/library/pathlib.html -- pathlib.Path (preferred over os.path)
- https://docs.python.org/3.12/library/enum.html -- Enum, StrEnum, IntEnum
- https://docs.python.org/3.12/library/asyncio.html -- asyncio
- https://docs.python.org/3/library/collections.html -- collections: defaultdict, Counter, deque, namedtuple
- https://docs.python.org/3/library/itertools.html -- itertools: chain, islice, groupby, product, takewhile

## Type System

- https://docs.python.org/3.12/library/typing.html -- Protocol, TypeVar, ParamSpec, overload
- https://mypy.readthedocs.io/en/stable/ -- mypy strict mode reference
- https://mypy.readthedocs.io/en/stable/config_file.html -- mypy configuration reference (strict mode options)
- https://mypy.readthedocs.io/en/stable/command_line.html -- mypy CLI flags: --strict, --disallow-any-generics, etc.
- https://mypy.readthedocs.io/en/stable/protocols.html -- mypy protocol documentation with examples
- https://peps.python.org/pep-0604/ -- X | Y union syntax (3.10+)
- https://peps.python.org/pep-0634/ -- Structural pattern matching (match/case)
- https://peps.python.org/pep-0695/ -- Type parameter syntax (3.12)
- https://peps.python.org/pep-0544/ -- Protocols for structural subtyping (static duck typing)

## PEPs Worth Knowing

- https://peps.python.org/pep-0008/ -- Style Guide
- https://peps.python.org/pep-0020/ -- The Zen of Python
- https://peps.python.org/pep-0257/ -- Docstring Conventions
- https://peps.python.org/pep-0526/ -- Variable annotations
- https://peps.python.org/pep-0572/ -- Walrus operator :=
- https://peps.python.org/pep-0585/ -- Type Hinting Generics In Standard Collections (use list[X] not List[X])
- https://peps.python.org/pep-0593/ -- Annotated

## Toolchain

- https://docs.astral.sh/ruff/ -- Ruff: extremely fast Python linter and formatter
- https://docs.astral.sh/ruff/rules/ -- Ruff rules reference
- https://black.readthedocs.io/en/stable/ -- Black formatter
- https://black.readthedocs.io/en/stable/usage_and_configuration/the_basics.html -- Black configuration in pyproject.toml
- https://pdm-project.org/latest/ -- PDM package manager
- https://pdm-project.org/en/latest/reference/configuration/ -- PDM configuration reference
- https://pip-audit.readthedocs.io/ -- pip-audit CVE scanner
- https://bandit.readthedocs.io/en/latest/ -- Bandit security linter
- https://bandit.readthedocs.io/en/latest/config.html -- Bandit configuration

## Data Classes and Modelling

- https://docs.python.org/3/library/dataclasses.html -- dataclasses: standard library frozen/slotted data classes
- https://www.attrs.org/en/stable/ -- attrs: powerful, composable class generation with validators
- https://docs.pydantic.dev/latest/ -- Pydantic v2: data validation and settings management

## Testing

- https://docs.pytest.org/en/stable/ -- pytest: full-featured test framework
- https://pytest-cov.readthedocs.io/en/latest/ -- pytest-cov: coverage reporting plugin
- https://docs.pytest.org/en/stable/reference/fixtures.html -- pytest built-in fixtures reference
- https://docs.pytest.org/en/stable/how-to/parametrize.html -- Parametrize guide
- https://hypothesis.readthedocs.io/en/latest/ -- Hypothesis: property-based testing
- https://factoryboy.readthedocs.io/en/stable/ -- factory_boy: test fixtures as factories
- https://lundberg.github.io/respx/ -- respx: HTTPX request mocking
- https://www.python-httpx.org/async/ -- HTTPX async client docs
- https://github.com/spulec/freezegun -- freezegun: freeze or travel time in tests
- https://pytest-asyncio.readthedocs.io/en/latest/ -- pytest-asyncio: async test functions
- https://coverage.readthedocs.io/en/latest/config.html -- coverage.py configuration reference
- https://coverage.readthedocs.io/en/latest/branch.html -- Branch coverage

## Architecture

- https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html -- Clean Architecture (Robert C. Martin)
- https://alistair.cockburn.us/hexagonal-architecture/ -- Hexagonal Architecture (Ports and Adapters)
- https://www.domainlanguage.com/ddd/ -- Domain-Driven Design resources by Eric Evans
- https://martinfowler.com/bliki/DomainDrivenDesign.html -- Martin Fowler's DDD overview
- https://en.wikipedia.org/wiki/SOLID -- SOLID principles overview
- https://martinfowler.com/articles/dipInTheWild.html -- Dependency Inversion in the wild
- https://python-dependency-injector.readthedocs.io/en/latest/ -- dependency-injector: containers, providers, wiring
- https://lagom.readthedocs.io/en/latest/ -- lagom: lightweight DI container
- https://martinfowler.com/eaaCatalog/serviceLayer.html -- Service Layer pattern
- https://martinfowler.com/eaaCatalog/repository.html -- Repository pattern
- https://martinfowler.com/bliki/CQRS.html -- CQRS: Command Query Responsibility Segregation
- https://martinfowler.com/eaaDev/EventSourcing.html -- Event Sourcing
- https://microservices.io/patterns/data/domain-event.html -- Domain Events
