/* ************************************************************************ */
/*                                                                          */
/*   SPDX-License-Identifier LGPL-2.1                                       */
/*   Copyright (C)                                                          */
/*   CEA (Commissariat à l'énergie atomique et aux énergies alternatives)   */
/*                                                                          */
/* ************************************************************************ */

/* --------------------------------------------------------------------------*/
/* --- Frama-C Selection History                                          ---*/
/* --------------------------------------------------------------------------*/

import React from 'react';
import * as Dome from 'dome';
import * as States from 'frama-c/states';
import { Button, ButtonGroup } from 'dome/primitive/controls';

Dome.addMenuItem({
  menu: 'View',
  id: 'ivette.history.prev',
  label: 'Previous location',
  key: 'Alt+Left',
  onClick: States.gotoPrev,
});

Dome.addMenuItem({
  menu: 'View',
  id: 'ivette.history.next',
  label: 'Next location',
  key: 'Alt+Right',
  onClick: States.gotoNext,
});

export default function History(): JSX.Element {
  const history = States.useHistory();
  const prev = history.prev[0]?.scope;
  const next = history.next[0]?.scope;
  const { label: prevLabel } = States.useDeclaration(prev);
  const { label: nextLabel } = States.useDeclaration(next);
  const prevTitle = prevLabel || 'Previous location';
  const nextTitle = nextLabel || 'Next location';
  return (
    <ButtonGroup>
      <Button
        icon="ANGLE.LEFT"
        onClick={States.gotoPrev}
        disabled={history.prev.length <= 0}
        title={prevTitle}
      />
      <Button
        icon="ANGLE.RIGHT"
        onClick={States.gotoNext}
        disabled={history.next.length <= 0}
        title={nextTitle}
      />
    </ButtonGroup>
  );
}

/* --------------------------------------------------------------------------*/
