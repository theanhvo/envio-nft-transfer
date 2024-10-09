/*
 * SPDX-License-Identifier: LicenseRef-AllRightsReserved
 *
 * License-Url: https://github.com/beramarket/torchbearer/LICENSES/LicenseRef-AllRightsReserved.txt
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes Krauser III <detroitmetalcrypto@gmail.com>
 *
 * SPDX-FileContributor: Johannes Krauser III <detroitmetalcrypto@gmail.com>
 */
/* eslint-disable @typescript-eslint/no-explicit-any */

type Writeable<T extends { [x: string]: any }, K extends string> = {
  [P in K]: T[P]
}

type Writeable<T> = { -readonly [P in keyof T]-?: T[P] }
