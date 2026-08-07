/* ************************************************************************ */
/*                                                                          */
/*   SPDX-License-Identifier LGPL-2.1                                       */
/*   Copyright (C)                                                          */
/*   CEA (Commissariat à l'énergie atomique et aux énergies alternatives)   */
/*                                                                          */
/* ************************************************************************ */

/* -------------------------------------------------------------------------- */
/* --- Sandbox Icons Gallery                                              --- */
/* --- Only appears in DEVEL mode.                                        --- */
/* -------------------------------------------------------------------------- */

import React from 'react';
import {
  Code, Title, LCD, LED, Meter, Icon, Badge,
  Label, Item, Cell, Data, Descr
} from 'dome/primitive/displays';
import { Section } from 'dome/frame/sidebars';
import { Scroll, Grid, Hbox, Vbox } from 'dome/layout/boxes';
import { registerSandbox } from 'ivette';
import {
  Button, CircButton, IconButton,
  Switch, Checkbox, Radio,
  SingleChoiceGroup, MultiChoiceGroup,
  Field, Select, Spinner
} from 'dome/primitive/controls';
import { ColorKind, colorKindList } from '../dome/renderer/primitive/colors';
import { RState } from 'dome/data/states';


/* -------------------------------------------------------------------------- */
/* --- Styles                                                             --- */
/* -------------------------------------------------------------------------- */

const gridStyle = {
  paddingLeft: 24,
  margin: 10,
  gap: '5px',
};

const flexCenter = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center'
};


/* -------------------------------------------------------------------------- */
/* --- Icon.tsx                                                         --- */
/* -------------------------------------------------------------------------- */

function Display(): React.JSX.Element {
  return (
    <Section
      key={'Dispalyed'} defaultUnfold
      label={'Display.tsx'}
    >
      <Grid style={gridStyle} columns="auto auto auto">
        <Title style={flexCenter} label='Component' />
        <Title style={flexCenter} label='Result' />
        <Title style={flexCenter} label='Details' />

        <Code label='<Label label="Label" />'/>
        <div style={flexCenter}><Label label='Label' /></div>
        <Hbox style={{
          gridRow: 'span 7',
          alignItems: 'center',
          borderLeft: 'dashed 1px',
          paddingLeft: '5px'
          }}>
            Constructed with makeLabel()
        </Hbox>

        <Code label='<Title label="Title" />'/>
        <div style={flexCenter}><Title label='Title' /></div>

        <Code label='<Descr label="Description" />'/>
        <div style={flexCenter}><Descr label='Description' /></div>

        <Code label='<Data label="Data" />'/>
        <div style={flexCenter}><Data label='Data' /></div>

        <Code label='<Code label="Code" />'/>
        <div style={flexCenter}><Code label='Code' /></div>

        <Code label='<Cell label="Cell" />'/>
        <div style={flexCenter}><Cell label='Cell' /></div>

        <Code label='<Item label="Item" />'/>
        <div style={flexCenter}><Item label='Item' /></div>

        <Code label='<Icon />'/>
        <div style={flexCenter}>
          <Icon id='SEARCH' title=''/>
          <Icon id='WARNING' kind='warning' title='kind=warning'/>
          <Icon id='TRASH'/>
          <Icon id='SPINNER' kind='primary'
            title='kind=primary, rotation auto'/>
        </div>
        <Hbox style={flexCenter}></Hbox>

        <Code label='<LED />'/>
        <div style={flexCenter}>
          <LED title='no props' />
          <LED status='active' title='status=active' />
          <LED status='warning'
           blink={true}
           title='status=warning, blink=true' />
        </div>
        <Hbox style={flexCenter}></Hbox>

        <Code label='<Meter />'/>
        <div style={flexCenter}>
          <Meter max={10} value={8}/>
        </div>
        <Hbox style={flexCenter}>value 8 for possible value 0-10</Hbox>

        <Code label='<LCD />'/>
        <Hbox style={flexCenter}><LCD label="LCD" icon='DISPLAY' /></Hbox>
        <Hbox style={flexCenter}></Hbox>

        <Code label='<Badge />'/>
        <div style={flexCenter}>
          <Badge label={'1'} />
          <Badge label={'10'} />
          <Badge label={'Badge'} />
          <Badge icon={'LOCK'} />
        </div>
        <Hbox style={flexCenter}></Hbox>

      </Grid>
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* --- Button.tsx                                                         --- */
/* -------------------------------------------------------------------------- */

interface ButtonKindProps {
  state: RState<ColorKind>;
}

function ButtonKind(props: ButtonKindProps): React.JSX.Element {
  const [ kind, setKind ] = props.state;
  function getNext(prev: ColorKind): ColorKind {
    const i = colorKindList.findIndex(v => v === prev);
    if(i === -1 || i+1 >= colorKindList.length) return colorKindList[0];
    return colorKindList[i+1];
  }

  const onclick = (kind: ColorKind): void => {
    setKind(getNext(kind));
  };

  return <Button onClick={() => onclick(kind)} label={kind}></Button>;
}

interface ButtonLineProps {
  selection?: boolean;
  details: string;
  children: React.JSX.Element;
}

function ButtonLine(props: ButtonLineProps): React.JSX.Element {
  const { selection = true, details, children } = props;

  const [selected, setSelected] = React.useState(false);
  const [disabled, setDisabled] = React.useState(false);
  const [kind, setKind] = React.useState<ColorKind>('default');

  const base = {
    kind: kind,
    disabled: disabled,
    title: 'click to select the button',
    selected: selection && selected,
    onClick: () => setSelected(v => !v)
  };

  return <>
    <div style={flexCenter}>
      { React.cloneElement(children, { ...base })}
    </div>
    <Icon style={flexCenter} id={selected ? 'CHECK' : 'CROSS'}
      kind={selected ? 'positive' : 'default'}/>
    <Checkbox style={flexCenter} selected={disabled}
      label='' onClick={() => setDisabled(v => !v)} />
    <div style={flexCenter}>
      <ButtonKind state={[kind, setKind]}></ButtonKind>
    </div>
    <Hbox style={flexCenter}>{details}</Hbox>
  </>;
}

function Buttons(): React.JSX.Element {
  return (
    <Section key={'buttons'} defaultUnfold
      label={'buttons: Button.tsx => based on BaseButton component'}
    >
      <Grid style={gridStyle} columns="auto auto auto auto 72px auto">
        <Title style={flexCenter} label='Component' />
        <Title style={flexCenter} label='Result' />
        <Title style={flexCenter} label='Selected' />
        <Title style={flexCenter} label='Disabled' />
        <Title style={flexCenter} label='Kind' />
        <Title style={flexCenter} label='Details' />

        {/* Button */}
        <Code label='<Button />' style={{ gridRow: 'span 6' }}/>

        <ButtonLine details='Empty button'><Button /></ButtonLine>
        <ButtonLine details='Known icon only'>
          <Button icon='FILTER'/>
        </ButtonLine>
        <ButtonLine selection={false}
          details='Known icon only + just the setSelected action,
          the button will be not selected'
        ><Button icon='FILTER'/>
        </ButtonLine>
        <ButtonLine details='Label only'><Button label='label'/></ButtonLine>
        <ButtonLine details='Label + known icon'>
          <Button label='label' icon='FILTER'/>
        </ButtonLine>
        <ButtonLine details='Label + unknown icon'>
          <Button  label='label' icon='"FILTER"' />
        </ButtonLine>

        {/* CircButton */}
        <Code label='<CircButton />'/>
        <ButtonLine details=''><CircButton icon='FILTER' /></ButtonLine>

        {/* IconButton */}
        <Code label='<IconButton />'/>
        <ButtonLine details=''><IconButton icon='FILTER' /></ButtonLine>

        {/* Switch */}
        <Code label='<Switch />'/>
        <ButtonLine details=''><Switch label='Switch'/></ButtonLine>

        {/* Checkbox */}
        <Code label='<Checkbox />'/>
        <ButtonLine details=''><Checkbox label='Checkbox'/></ButtonLine>

        {/* Radio */}
        <Code label='<Radio />'/>
        <ButtonLine details=''><Radio label='Radio'/></ButtonLine>

      </Grid>
    </Section>
  );
}

/** ********* Button group ****************************************************/
interface ButtonGroupLineProps {
  values: {
    value: string,
    kind?: ColorKind,
    icon?: string,
    disabled?: boolean
  }[];
  multiple?: boolean,
  separate?: boolean,
  vertical?: boolean,
  details: string,
  /** default to button */
  type?: 'radio' | 'button' | 'checkbox'
}

function ButtonGroupLine(props: ButtonGroupLineProps): React.JSX.Element {
  const {
    values, separate, vertical, multiple, details, type = 'button'
  } = props;
  const [disabled, setDisabled] = React.useState(false);
  const [lineValues, setLineValues] = React.useState<string>();

  const control: React.JSX.Element[] = values.map(e => {
    if(type === 'radio') return <Radio key={e.value}
      value={e.value}
      label={e.value}
      kind={e.kind || 'default'}
      disabled={e.disabled}/>;
    else if(type === 'checkbox') return <Checkbox key={e.value}
      value={e.value}
      label={e.value}
      kind={e.kind || 'default'}
      disabled={e.disabled}/>;

    return <Button key={e.value} value={e.value}
        label={e.value} kind={e.kind || 'default'}
        icon={e.icon} disabled={e.disabled}/>;
  });


  return <>
    <div style={flexCenter}>
    {multiple ?
      <MultiChoiceGroup disabled={disabled}
        separate={separate} vertical={vertical}
        onChange={(v) => setLineValues(v.join(' | '))}
      >
        { control }
      </MultiChoiceGroup>
      :
      <SingleChoiceGroup disabled={disabled}
        separate={separate} vertical={vertical}
        onChange={(v) => setLineValues(v?.toString())}
        >
        { control }
      </SingleChoiceGroup>
    }
    </div>
    <Hbox style={flexCenter}>{lineValues}</Hbox>
    <Checkbox style={flexCenter} selected={disabled}
      label='' onClick={() => setDisabled(v => !v)} />
    <Hbox style={flexCenter}>{details}</Hbox>
  </>;
}

function ButtonGroups(): React.JSX.Element {
  return <Section key={'buttonGroups'}
      defaultUnfold
      label={'Buttons Groups: Button.tsx'}
    >
      <Grid style={gridStyle} columns="auto auto auto auto">
        <Title style={flexCenter} label='Result' />
        <Title style={flexCenter} label='Values' />
        <Title style={flexCenter} label='Disabled' />
        <Title style={flexCenter} label='Details' />

        <ButtonGroupLine
          values={[
            { value: 'default' },
            { value: 'primary', kind: 'primary' },
            { value: 'positive', kind: 'positive' },
            { value: 'warning', kind: 'warning' },
            { value: 'negative', kind: 'negative' },
            { value: 'disabled', kind: 'negative', disabled: true },
          ]}
          details='buttonGroup glued: option "separate" by default'
        />
        <ButtonGroupLine
          values={[
            { value: 'default' },
            { value: 'primary', kind: 'primary' },
            { value: 'positive', kind: 'positive' },
            { value: 'warning', kind: 'warning' },
            { value: 'negative', kind: 'negative' },
            { value: 'disabled', kind: 'negative', disabled: true },
          ]}
          separate={true}
          details='buttonGroup separated'
        />
        <ButtonGroupLine
          values={[
            { value: 'Value 1', icon: 'FILTER' },
            { value: 'Value 2', icon: 'FILTER' },
            { value: 'Value 3', icon: 'FILTER' },
            { value: 'disabled', icon: 'FILTER', disabled: true },
            { value: 'Value 5', icon: 'FILTER' },
          ]}
          multiple={true}
          separate={true}
          details='buttonGroup separated and multiple choices'
        />
        <ButtonGroupLine
          values={[
            { value: 'default' },
            { value: 'primary', kind: 'primary' },
            { value: 'positive', kind: 'positive' },
            { value: 'warning', kind: 'warning' },
            { value: 'negative', kind: 'negative' },
            { value: 'disabled', kind: 'negative', disabled: true },
          ]}
          details='buttonGroup style radio, option vertical=true'
          type='radio'
          vertical={true}
        />
        <ButtonGroupLine
          values={[
            { value: 'default' },
            { value: 'primary', kind: 'primary' },
            { value: 'positive', kind: 'positive' },
            { value: 'warning', kind: 'warning' },
            { value: 'negative', kind: 'negative' },
            { value: 'disabled', kind: 'negative', disabled: true },
          ]}
          multiple={true}
          details='buttonGroup style checkbox, option vertical=true'
          type='checkbox'
          vertical={true}
        />
      </Grid>
  </Section>;
}

/* -------------------------------------------------------------------------- */
/* --- inputs.tsx                                                         --- */
/* -------------------------------------------------------------------------- */

function SelectMenuLine(): React.JSX.Element {
  const [value, setValue] = React.useState('1');
  const [disabled, setDisabled] = React.useState(false);

  return <>
    <Code label='<Select />'/>
    <div style={flexCenter}>
      <Select
      placeholder='ddd'
        disabled={disabled}
        value={value}
        onChange={setValue as (newValue?: string) => void}
      >
        <option key={1} value={'1'}>{"select 1"}</option>
        <option key={2} value={'2'}>{"select 2"}</option>
        <option key={3} value={'3'}>{"select 3"}</option>
        <option key={4} value={'4'}>{"select 4"}</option>
        <option key={5} value={'5'}>{"select 5"}</option>
        <option key={6} value={'6'}>{"select 6"}</option>
      </Select>
    </div>

    <Hbox style={flexCenter}>{value}</Hbox>
    <Checkbox style={flexCenter}
      label='' selected={disabled}
      onClick={() => setDisabled(v => !v)} />
    <Hbox style={flexCenter}></Hbox>
  </>;
}

function SpinnerLine(): React.JSX.Element {
  const [value, setValue] = React.useState(0);
  const [disabled, setDisabled] = React.useState(false);

  return <>
    <Code label='<Spinner />'/>
    <div style={flexCenter}>
      <Spinner value={value} onChange={setValue} disabled={disabled}/>
    </div>
    <Hbox style={flexCenter}>{value}</Hbox>
    <Checkbox style={flexCenter}
      label='' selected={disabled}
      onClick={() => setDisabled(v => !v)} />
    <Hbox style={flexCenter}></Hbox>
  </>;
}

function FieldLine(): React.JSX.Element {
  const [value, setValue] = React.useState('');
  const [disabled, setDisabled] = React.useState(false);
  const [editing, setEditing] = React.useState('');

  return <>
    <Code label='<Field />'/>
    <div style={flexCenter}>
      <Field placeholder='Your value'
        value={value}
        onEdited={setEditing}
        onChange={(v: string) => { setValue(v); setEditing(''); }}
        disabled={disabled}
        style={editing !== '' ? { background: 'orange' }: {}}
        />
      <Button
        label="Valid"
        onClick={() =>  { setValue(editing); setEditing(''); }}
        />
    </div>
    <Hbox style={flexCenter}>{value}</Hbox>
    <Checkbox style={flexCenter}
      label='' selected={disabled}
      onClick={() => setDisabled(v => !v)} />
    <Vbox style={flexCenter}>
      <p>background orange ={'>'} editing</p>
      <p>valid with button or press enter</p>
      <p>return with escape</p>
    </Vbox>
  </>;
}

function Inputs(): React.JSX.Element {

  return <Section key={'inputs'} defaultUnfold label={'inputs'}>
      <Grid style={gridStyle} columns="auto auto auto auto auto">
        <Title style={flexCenter} label='Component' />
        <Title style={flexCenter} label='Result' />
        <Title style={flexCenter} label='Value' />
        <Title style={flexCenter} label='Disabled' />
        <Title style={flexCenter} label='Details' />

        <SpinnerLine /> {/* Spinner */}
        <FieldLine /> {/* Field */}
        <SelectMenuLine /> {/* SelectMenu */}

      </Grid>
  </Section>;
}



/* -------------------------------------------------------------------------- */
/* --- Sandbox                                                            --- */
/* -------------------------------------------------------------------------- */

function Controls(): JSX.Element {
  return <Scroll>
      <div style={{ margin: '20px' }}>
      <Display />
      <Buttons/>
      <ButtonGroups/>
      <Inputs />
  </div>
    </Scroll>;
}

registerSandbox({
  id: 'sandbox.controls',
  label: 'Displays & Controls',
  children: <Controls />,
});

/* -------------------------------------------------------------------------- */
