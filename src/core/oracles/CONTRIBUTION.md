# Contributing to Decentralized Oracle Adapters

We're thrilled you're interested in contributing to the Decentralized Oracle Adapters project! Your contributions help us build a more robust and flexible system for integrating decentralized oracle solutions in smart contracts.

This document outlines guidelines for reporting bugs, suggesting features, and submitting pull requests. We aim to foster an open, welcoming, and inclusive community.

## Code of Conduct

Please note that this project is released with a Contributor Code of Conduct. By participating in this project, you agree to abide by its terms. We expect all contributors to follow the Code of Conduct.

## How Can I Contribute?

There are many ways to contribute, not just by writing code.

### 🐛 Reporting Bugs

A bug is a demonstrable problem caused by the code in the repository.

1.  **Check Existing Issues**: Before submitting a new bug report, please check the [issues page](https://github.com/your-username/decentralized-oracle-adapters/issues) (replace with actual link) to see if the bug has already been reported.
2.  **Open a New Issue**: If it's a new bug, please open a new issue and provide the following information:
    *   A clear and concise description of the bug.
    *   Steps to reproduce the behavior.
    *   Expected behavior.
    *   Actual behavior.
    *   Any relevant error messages or console output.
    *   Your environment details (e.g., Solidity version, Hardhat/Foundry version).

### ✨ Suggesting Features

We welcome ideas for new features, improvements, or enhancements!

1.  **Check Existing Discussions/Issues**: See if your feature has already been discussed or requested.
2.  **Open a New Issue**: If it's a new suggestion, open an issue labeled `feature` and clearly describe:
    *   The problem your feature solves.
    *   The proposed solution or enhancement.
    *   Any potential alternatives or considerations.
    *   How it would benefit the project and users.

### 📝 Submitting Pull Requests

Contributing code through pull requests is a direct way to improve the project.

1.  **Fork the Repository**: Start by forking the `decentralized-oracle-adapters` repository to your GitHub account.
2.  **Clone Your Fork**: Clone your forked repository to your local machine:
    ```bash
    git clone https://github.com/your-username/decentralized-oracle-adapters.git # Replace with your fork's URL
    cd decentralized-oracle-adapters
    ```
3.  **Create a New Branch**: Create a new branch for your changes. Use a descriptive name, e.g., `feature/add-pyth-v2`, `fix/compiler-warning`:
    ```bash
    git checkout -b feature/your-feature-name
    ```
4.  **Set Up Development Environment**: Ensure your development environment is set up as described in the `README.md` (e.g., Node.js, npm, Hardhat/Foundry).
5.  **Make Your Changes**: Implement your bug fix or feature.
    *   **Coding Standards**: Adhere to the existing coding style and practices within the project. For Solidity, this typically includes Natspec comments, clear error messages, and gas-efficient code.
    *   **Testing**: Write comprehensive unit tests for your changes. All new features and bug fixes should have corresponding tests that pass.
6.  **Commit Your Changes**: Commit your changes with a clear and concise commit message. Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) if possible (e.g., `feat: Add new adapter for X`, `fix: Correct Y calculation`).
    ```bash
    git commit -m 'feat: Add a new XYZ oracle adapter'
    ```
7.  **Push to Your Fork**: Push your branch to your forked repository on GitHub:
    ```bash
    git push origin feature/your-feature-name
    ```
8.  **Open a Pull Request**: Go to the original `decentralized-oracle-adapters` repository on GitHub and open a new Pull Request from your branch.
    *   **Provide a Clear Description**: Explain the purpose of your PR, the changes you made, and any relevant context. Reference the issue it addresses (e.g., `Fixes #123`, `Implements #456`).
    *   **Ensure Tests Pass**: Verify that all automated tests pass.
    *   **Request Review**: Your PR will be reviewed by maintainers. Be prepared to discuss your changes and make further adjustments if requested.

## Development Setup

Please refer to the `README.md` for detailed instructions on setting up your local development environment and installing dependencies.

## Licensing

By contributing to this project, you agree that your contributions will be licensed under the project's [BUSL-1.1 license](https://spdx.org/licenses/BUSL-1.1.html).

Thank you for your valuable contributions!

